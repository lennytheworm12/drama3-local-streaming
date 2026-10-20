import os
import struct
import tempfile
import unittest

from expert_stats import counts, frames_and_prompt, locality, lru_misses_per_frame


def write_log(path, records, used):
    """records: list of (n_past, {layer: [ids per row]})."""
    with open(path, "wb") as f:
        for n_past, per in records:
            rows = len(next(iter(per.values())))
            f.write(struct.pack("<iii", n_past, rows, len(per)))
            for layer, rr in per.items():
                f.write(struct.pack("<i", layer))
                for ids in rr:
                    assert len(ids) == used
                    f.write(struct.pack(f"<{used}i", *ids))


class ExpertStatsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile(delete=False)
        self.tmp.close()
        # one prompt block of 2 rows, then 3 generated frames, 2 layers, used=2
        write_log(self.tmp.name, [
            (0, {0: [(1, 2), (3, 4)], 1: [(5, 6), (7, 8)]}),
            (2, {0: [(1, 2)], 1: [(5, 6)]}),
            (3, {0: [(1, 9)], 1: [(5, 6)]}),
            (4, {0: [(9, 1)], 1: [(6, 7)]}),
        ], used=2)

    def tearDown(self):
        os.unlink(self.tmp.name)

    def test_parse_splits_prompt_and_frames(self):
        frames, prompt = frames_and_prompt(self.tmp.name, 2)
        self.assertEqual(len(frames), 3)
        self.assertEqual(sum(prompt.values()), 8)
        self.assertEqual(frames[1], {0: (1, 9), 1: (5, 6)})

    def test_counts(self):
        frames, _ = frames_and_prompt(self.tmp.name, 2)
        c = counts(frames)
        self.assertEqual(c[(0, 1)], 3)
        self.assertEqual(c[(1, 6)], 3)
        self.assertEqual(sum(c.values()), 12)

    def test_locality(self):
        frames, _ = frames_and_prompt(self.tmp.name, 2)
        # frame1 vs frame0: layer0 {1} of (1,9) -> 1 hit, layer1 2 hits; frame2 vs frame1: layer0 2 hits, layer1 1 hit
        self.assertAlmostEqual(locality(frames), 6 / 8)

    def test_lru(self):
        frames, _ = frames_and_prompt(self.tmp.name, 2)
        cases = [
            ("capacity 0 misses every pick", 0, frozenset(), 12 / 3),
            ("big cache misses only first touches", 100, frozenset(), 6 / 3),  # 1,2,9 | 5,6,7
            ("pinned keys never miss", 100, frozenset({(0, 1), (1, 5), (1, 6)}), 3 / 3),
        ]
        for name, cap, pinned, want in cases:
            with self.subTest(name):
                self.assertAlmostEqual(lru_misses_per_frame(frames, cap, pinned), want)

    def test_empty_log(self):
        empty = tempfile.NamedTemporaryFile(delete=False)
        empty.close()
        try:
            frames, prompt = frames_and_prompt(empty.name, 2)
            self.assertEqual((frames, sum(prompt.values())), ([], 0))
            self.assertEqual(locality(frames), 0.0)
            self.assertEqual(lru_misses_per_frame(frames, 10), 0.0)
        finally:
            os.unlink(empty.name)


if __name__ == "__main__":
    unittest.main()
