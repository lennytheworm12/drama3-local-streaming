"""Client for `speech worker` (JSON Lines protocol 3, docs/worker.md in speech.cpp).

One Worker owns one child process. Requests run one at a time, so the client is
synchronous: send a request, read lines until that id's terminal message.
"""
import base64
import json
import os
import queue
import subprocess
import threading
import time

TERMINAL = ("end", "error", "cancelled")


class WorkerError(RuntimeError):
    pass


class Worker:
    def __init__(self, binary, model, args=(), ready_timeout_s=1200, stderr_path=None):
        self._stderr = open(stderr_path, "wb") if stderr_path else subprocess.DEVNULL
        t0 = time.monotonic()
        self.proc = subprocess.Popen(
            [binary, "worker", model, *args],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self._stderr,
        )
        self._lines = queue.Queue(maxsize=4096)
        threading.Thread(target=self._pump, daemon=True).start()
        msg = self._next(ready_timeout_s)
        if msg.get("type") != "ready":
            raise WorkerError(f"worker did not start: {msg}")
        self.ready = msg
        self.load_s = time.monotonic() - t0

    @property
    def pid(self):
        return self.proc.pid

    def _pump(self):
        for raw in self.proc.stdout:
            self._lines.put(raw)
        self._lines.put(None)

    def _next(self, timeout_s):
        try:
            raw = self._lines.get(timeout=timeout_s)
        except queue.Empty:
            raise WorkerError(f"no message from worker in {timeout_s} s")
        if raw is None:
            raise WorkerError(f"worker exited with {self.proc.wait()}")
        msg = json.loads(raw)
        if not isinstance(msg, dict) or "type" not in msg:
            raise WorkerError(f"not a protocol message: {raw[:200]!r}")
        return msg

    def _send(self, msg):
        self.proc.stdin.write((json.dumps(msg) + "\n").encode())
        self.proc.stdin.flush()

    def synthesize(self, rid, text, idle_timeout_s=600, **options):
        """Returns (pcm_bytes, end_msg, first_chunk_s, total_s)."""
        t0 = time.monotonic()
        self._send({"type": "synthesize", "id": rid, "text": text, **options})
        pcm, first = [], None
        while True:
            msg = self._next(idle_timeout_s)
            if msg.get("id") != rid:
                raise WorkerError(f"unexpected message for another id: {msg}")
            if msg["type"] == "chunk":
                if first is None:
                    first = time.monotonic() - t0
                pcm.append(base64.b64decode(msg["pcm"]))
            elif msg["type"] in TERMINAL:
                if msg["type"] != "end":
                    raise WorkerError(f"synthesize {rid}: {msg}")
                return b"".join(pcm), msg, first, time.monotonic() - t0

    def transcribe(self, rid, pcm, sample_rate, idle_timeout_s=600, chunk_bytes=1 << 20, **options):
        for seq, i in enumerate(range(0, len(pcm), chunk_bytes)):
            self._send({"type": "chunk", "id": rid, "seq": seq,
                        "pcm": base64.b64encode(pcm[i:i + chunk_bytes]).decode()})
        self._send({"type": "transcribe", "id": rid, "sample_rate": sample_rate, **options})
        while True:
            msg = self._next(idle_timeout_s)
            if msg.get("id") == rid and msg["type"] in TERMINAL:
                if msg["type"] != "end":
                    raise WorkerError(f"transcribe {rid}: {msg}")
                return msg

    def close(self, timeout_s=60):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=timeout_s)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        if self._stderr is not subprocess.DEVNULL:
            self._stderr.close()


class Sampler:
    """Samples a process's RSS (anon/file) and whole-GPU memory once a second."""

    def __init__(self, pid, period_s=1.0):
        self.pid, self.period_s = pid, period_s
        self.peak = {"rss_kb": 0, "anon_kb": 0, "file_kb": 0, "vram_mib": 0}
        self._stop = threading.Event()
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()

    def _run(self):
        while not self._stop.wait(self.period_s):
            if os.name == "nt":
                self._windows_rss()
            else:
                try:
                    with open(f"/proc/{self.pid}/status") as f:
                        for line in f:
                            k, _, v = line.partition(":")
                            key = {"VmRSS": "rss_kb", "RssAnon": "anon_kb", "RssFile": "file_kb"}.get(k)
                            if key:
                                self.peak[key] = max(self.peak[key], int(v.split()[0]))
                except FileNotFoundError:
                    return
            try:
                out = subprocess.run(
                    ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                    capture_output=True, text=True, timeout=10).stdout
                self.peak["vram_mib"] = max(self.peak["vram_mib"], int(out.split()[0]))
            except (subprocess.TimeoutExpired, ValueError, IndexError):
                pass

    def _windows_rss(self):
        """Peak working set and private bytes via psapi (Windows has no /proc)."""
        import ctypes
        from ctypes import wintypes

        class PMC(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                        ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                        ("PrivateUsage", ctypes.c_size_t)]
        h = ctypes.windll.kernel32.OpenProcess(0x1000 | 0x0010, False, self.pid)  # QUERY_LIMITED_INFORMATION | VM_READ
        if not h:
            return
        try:
            pmc = PMC()
            pmc.cb = ctypes.sizeof(PMC)
            if ctypes.windll.psapi.GetProcessMemoryInfo(h, ctypes.byref(pmc), pmc.cb):
                self.peak["rss_kb"] = max(self.peak["rss_kb"], pmc.PeakWorkingSetSize // 1024)
                self.peak["anon_kb"] = max(self.peak["anon_kb"], pmc.PeakPagefileUsage // 1024)  # private commit
        finally:
            ctypes.windll.kernel32.CloseHandle(h)

    def stop(self):
        self._stop.set()
        self._t.join(timeout=5)
        return dict(self.peak)


def gpu_used_mib():
    out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                         capture_output=True, text=True, timeout=10).stdout
    return int(out.split()[0])


def read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def append_jsonl(path, rec):
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        f.flush()
        os.fsync(f.fileno())
