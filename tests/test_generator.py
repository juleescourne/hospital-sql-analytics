import unittest
from datetime import datetime
from scripts.generate_sample_data import build


class GeneratorTest(unittest.TestCase):
    def test_lifetimes_and_relationships(self):
        for seed in (7, 42):
            with self.subTest(seed=seed):
                data = build(400, seed)
                patients = {p['Id']: p for p in data['patients']}
                encounters = {e['Id']: e for e in data['encounters']}
                self.assertEqual(len(patients), 400)
                self.assertEqual(len(encounters), len(data['encounters']))
                for e in encounters.values():
                    p = patients[e['PATIENT']]
                    self.assertGreaterEqual(e['START'][:10], p['BIRTHDATE'])
                    if p['DEATHDATE']:
                        self.assertLessEqual(e['START'][:10], p['DEATHDATE'])
                        if e['STOP']:
                            self.assertLessEqual(e['STOP'][:10], p['DEATHDATE'])
                    self.assertLess(e['START'], '2023-01-01')
                for act in data['procedures']:
                    e = encounters[act['ENCOUNTER']]
                    self.assertEqual(act['PATIENT'], e['PATIENT'])
                    self.assertGreaterEqual(act['STOP'], act['START'])

    def test_missing_and_invalid_values_are_distinct(self):
        encounters = build(400, 42)['encounters']
        self.assertEqual(sum(e['STOP'] == '' for e in encounters), len(encounters) // 120)
        self.assertEqual(sum(bool(e['STOP']) and e['STOP'] < e['START'] for e in encounters), 2)
        self.assertEqual(sum(e['STOP'] == e['START'] for e in encounters), 3)
        self.assertEqual(sum(e['PAYER'] == '' for e in encounters), len(encounters) // 200)

    def test_reproducible_without_global_random_state(self):
        self.assertEqual(build(20, 42), build(20, 42))
        self.assertNotEqual(build(20, 42), build(20, 7))

    def test_empty_population_is_rejected(self):
        with self.assertRaises(ValueError):
            build(0, 42)


if __name__ == '__main__':
    unittest.main()
