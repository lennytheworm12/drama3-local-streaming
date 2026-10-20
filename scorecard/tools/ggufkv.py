import struct, sys
f = open(sys.argv[1], "rb")
assert f.read(4) == b"GGUF"
ver, nt, nkv = struct.unpack("<IQQ", f.read(20))
def s(): n, = struct.unpack("<Q", f.read(8)); return f.read(n).decode("utf-8", "replace")
sz = {0:1,1:1,2:2,3:2,4:4,5:4,6:4,7:1,10:8,11:8,12:8}
fmt = {0:"B",1:"b",2:"H",3:"h",4:"I",5:"i",6:"f",7:"?",10:"Q",11:"q",12:"d"}
def val(t):
    if t == 8: return s()
    if t == 9:
        et, n = struct.unpack("<IQ", f.read(12))
        vals = [val(et) for _ in range(n)]
        return f"[array {n}]"
    return struct.unpack("<" + fmt[t], f.read(sz[t]))[0]
for _ in range(nkv):
    k = s(); t, = struct.unpack("<I", f.read(4)); v = val(t)
    if any(w in k for w in ("expert", "block_count", "embedding_length", "feed_forward", "head_count")) and "text" in k or "num_" in k:
        print(k, v)
