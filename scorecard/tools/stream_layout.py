"""Writes Drama 3's routed experts laid out whole, for SPEECH_STREAM_FILE: for layer 0..L-1 and expert 0..E-1, the
expert's ffn_gate_exps, ffn_up_exps and ffn_down_exps slices back to back, each expert padded to 4 KiB, no header.

    python stream_layout.py MODEL.gguf OUT.experts

Expert e of layer l starts at (l * E + e) * stride, stride = the three slices' bytes rounded up to 4 KiB, which is
how the engine finds it; one unbuffered read then fetches the whole expert.
"""
import struct
import sys

ALIGN = 4096
SCALARS = {0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i", 6: "f", 7: "?", 10: "Q", 11: "q", 12: "d"}


def read_gguf_tensors(path):
    """The tensors of a GGUF file: {name: (dims, type, absolute offset)}, and the data alignment."""
    with open(path, "rb") as f:
        def r(fmt):
            return struct.unpack("<" + fmt, f.read(struct.calcsize("<" + fmt)))[0]

        def s():
            return f.read(r("Q")).decode("utf-8", "replace")

        def skip(t):
            if t == 8:
                s()
            elif t == 9:
                et, n = r("I"), r("Q")
                for _ in range(n):
                    skip(et)
            else:
                f.read(struct.calcsize("<" + SCALARS[t]))

        assert f.read(4) == b"GGUF"
        r("I")
        n_tensors, n_kv = r("Q"), r("Q")
        alignment = 32
        for _ in range(n_kv):
            key, t = s(), r("I")
            if key == "general.alignment":
                alignment = r("I")
            else:
                skip(t)
        tensors = {}
        for _ in range(n_tensors):
            name = s()
            dims = [r("Q") for _ in range(r("I"))]
            typ, off = r("I"), r("Q")
            tensors[name] = (dims, typ, off)
        data = (f.tell() + alignment - 1) // alignment * alignment
    return {k: (d, t, data + o) for k, (d, t, o) in tensors.items()}


def main():
    src, out = sys.argv[1], sys.argv[2]
    tensors = read_gguf_tensors(src)
    layers = 1 + max(int(k.split(".")[1]) for k in tensors if k.startswith("blk."))
    names = ("ffn_gate_exps", "ffn_up_exps", "ffn_down_exps")
    first = [tensors[f"blk.0.{n}"] for n in names]
    experts = first[0][0][2]
    # bytes of one expert's slice of each tensor: rows of ne[1], each ne[0] values in the type's blocks
    blocks = {8: (32, 34), 12: (256, 144), 13: (256, 176), 14: (256, 210)}  # Q8_0, Q4_K, Q5_K, Q6_K
    per = []
    for dims, typ, _ in first:
        if typ not in blocks:
            sys.exit(f"type {typ} is not one this script sizes")
        bs, bb = blocks[typ]
        per.append(dims[0] // bs * bb * dims[1])
    stride = (sum(per) + ALIGN - 1) // ALIGN * ALIGN
    print(f"{layers} layers x {experts} experts, slices {per} bytes, stride {stride}")
    pad = b"\0" * (stride - sum(per))
    with open(src, "rb") as f, open(out, "wb") as o:
        for l in range(layers):
            offs = [tensors[f"blk.{l}.{n}"][2] for n in names]
            blobs = []
            for off, size in zip(offs, per):
                f.seek(off)
                blobs.append(f.read(size * experts))
            for e in range(experts):
                for blob, size in zip(blobs, per):
                    o.write(blob[e * size:(e + 1) * size])
                o.write(pad)
            print(f"layer {l} done", flush=True)


if __name__ == "__main__":
    main()
