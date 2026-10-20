import math
import os
import struct
import tempfile
import unittest

from fidelity import compare, kl, read


def write(path, records):
    with open(path, "wb") as f:
        for step, head, vals in records:
            f.write(struct.pack("<iii", step, head, len(vals)))
            f.write(struct.pack(f"<{len(vals)}f", *vals))


class FidelityTest(unittest.TestCase):
    def test_kl_cases(self):
        cases = [
            ("identical is zero", [1.0, 2.0, 3.0], [1.0, 2.0, 3.0], 0.0),
            ("shift invariant", [1.0, 2.0, 3.0], [11.0, 12.0, 13.0], 0.0),
            ("two-way known value", [0.0, 0.0], [math.log(3), 0.0], 0.5 * math.log(0.5 / 0.75) + 0.5 * math.log(0.5 / 0.25)),
        ]
        for name, p, q, want in cases:
            with self.subTest(name):
                self.assertAlmostEqual(kl(p, q), want, places=6)

    def test_compare_and_missing(self):
        d = tempfile.mkdtemp()
        a, b = os.path.join(d, "a"), os.path.join(d, "b")
        write(a, [(0, 0, [1, 2, 3]), (0, 1, [3, 2, 1]), (1, 0, [0, 0, 5])])
        write(b, [(0, 0, [1, 2, 3]), (0, 1, [1, 2, 3])])
        per_head, missing = compare(read(a), read(b))
        self.assertEqual(missing, 1)
        self.assertEqual(per_head[0][1:], [1, 1])  # top-1 agrees, 1 step
        self.assertEqual(per_head[1][1:], [0, 1])  # argmax differs
        self.assertGreater(per_head[1][0], 0)


if __name__ == "__main__":
    unittest.main()
