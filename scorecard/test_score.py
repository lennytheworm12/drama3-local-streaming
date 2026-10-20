import unittest

from score import edit_distance, error_rates, flags, normalize


class NormalizeTest(unittest.TestCase):
    CASES = [
        ("punctuation", "Wait. Did you hear that?", "wait did you hear that"),
        ("year", "In 1969, two", "in nineteen sixty nine two"),
        ("year 2005", "2005", "two thousand five"),
        ("thousands comma", "6,000 meters", "six thousand meters"),
        ("time", "opens at 9:30", "opens at nine thirty"),
        ("hyphen digits", "a 10-year-old", "a ten year old"),
        ("hyphen words", "a ten-year-old", "a ten year old"),
        ("apostrophe kept", "Let's go, bakery's step", "let's go bakery's step"),
        ("curly apostrophe", "I’m here", "i'm here"),
        ("quote marks dropped", "'quoted' word", "quoted word"),
        ("doctor abbrev", "Dr. Patel", "doctor patel"),
        ("empty", "", ""),
        ("zero", "0", "zero"),
    ]

    def test_cases(self):
        for name, text, want in self.CASES:
            with self.subTest(name):
                self.assertEqual(normalize(text), want)


class ErrorRateTest(unittest.TestCase):
    CASES = [
        ("identical", "the cat sat", "The cat sat.", 0.0),
        ("one substitution", "the cat sat", "the bat sat", 1 / 3),
        ("deletion", "the cat sat", "the sat", 1 / 3),
        ("insertion", "the cat", "the black cat", 1 / 2),
        ("empty hyp", "the cat", "", 1.0),
        ("number forms agree", "In 1969 they left", "in nineteen sixty-nine they left", 0.0),
        ("japanese punctuation ignored", "はい。そうです！", "はい、そうです", 0.0),
        ("japanese one char wrong of 6", "今日は晴れです", "今日は雨です", 2 / 7),
        ("full-width digits match ascii", "１２３です", "123です", 0.0),
    ]

    def test_wer(self):
        for name, ref, hyp, want in self.CASES:
            with self.subTest(name):
                self.assertAlmostEqual(error_rates(ref, hyp)[0], want)

    def test_edit_distance_bounds(self):
        for a, b, want in [("", "", 0), ("a", "", 1), ("", "abc", 3), ("kitten", "sitting", 3)]:
            self.assertEqual(edit_distance(a, b), want)


class FlagsTest(unittest.TestCase):
    BASE = {"stop": "complete", "wer": 0.0, "longest_pause_s": 0.3, "words_per_s": 2.8}
    CASES = [
        ("clean", {}, []),
        ("runaway", {"stop": "max_seconds"}, ["max_seconds"]),
        ("wer boundary not flagged", {"wer": 0.2}, []),
        ("wer over", {"wer": 0.21}, ["wer>20%"]),
        ("long pause", {"longest_pause_s": 2.05}, ["pause>2s"]),
        ("too slow", {"words_per_s": 1.4}, ["rate"]),
        ("too fast", {"words_per_s": 4.6}, ["rate"]),
        ("rate edges ok", {"words_per_s": 1.5}, []),
    ]

    def test_cases(self):
        for name, change, want in self.CASES:
            with self.subTest(name):
                self.assertEqual(flags({**self.BASE, **change}), want)


if __name__ == "__main__":
    unittest.main()
