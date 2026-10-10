"""Tester les vraies requêtes sur de petits cas, dans une transaction annulée."""
import csv
import io
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def query_section(filename, number):
    text = (ROOT / 'queries' / filename).read_text()
    parts = re.split(r'(?m)^-- (\d+)\. ', text)
    for index in range(1, len(parts), 2):
        if int(parts[index]) == number:
            return '-- ' + parts[index + 1]
    raise ValueError(f'Section {number} absente de {filename}')


def run_query(command, sql):
    result = subprocess.run(command, input=sql, text=True, capture_output=True, check=True)
    return list(csv.DictReader(io.StringIO(result.stdout), delimiter='\t'))


SETUP = '''
START TRANSACTION;
DELETE FROM procedures;
DELETE FROM encounters;
DELETE FROM patients;
DELETE FROM organizations;
DELETE FROM payers;
INSERT INTO organizations (Id, NAME) VALUES ('test-org', 'Fictif');
INSERT INTO patients (Id, BIRTHDATE) VALUES ('test-patient', '2000-01-01');
'''


def encounter(identifier, start, stop, cost=100, coverage=50):
    end = 'NULL' if stop is None else "'" + stop + "'"
    return f"""INSERT INTO encounters
        (Id, START, STOP, PATIENT, ORGANIZATION, ENCOUNTERCLASS, TOTAL_CLAIM_COST, PAYER_COVERAGE)
        VALUES ('{identifier}', '{start}', {end}, 'test-patient', 'test-org', 'ambulatory', {cost}, {coverage});\n"""


def main(command):
    def case(fixture, file, section):
        # Aucun DDL : les suppressions et insertions sont toutes annulées, même à
        # la fermeture de la connexion en cas d'erreur SQL.
        return run_query(command, SETUP + fixture + query_section(file, section) + '\nROLLBACK;')

    first = encounter('a', '2020-01-01 00:00:00', '2020-01-01 12:00:00')
    missing = first + encounter('b', '2020-01-05 12:00:00', None) + encounter('c', '2020-01-10 12:00:00', '2020-01-10 13:00:00')
    rows = case(missing, '03_encounter_analytics.sql', 3)
    assert rows[0]['return_encounters_within_30_days'] == '1'
    assert float(rows[0]['average_gap_days']) == 4.0, rows
    rows = case(missing, '06_window_functions_cohorts.sql', 6)
    assert sum(int(r['encounter_count']) for r in rows) == 1, rows
    print('OK : passage suivant conservé malgré une fin manquante (LEAD et LAG).')

    for next_start, stop, expected in [
        ('2020-01-31 12:00:00', '2020-01-01 12:00:00', 1),
        ('2020-01-31 12:00:01', '2020-01-01 12:00:00', 0),
        ('2020-01-01 11:59:59', '2020-01-01 12:00:00', 0),
        ('2020-01-02 12:00:00', '2019-12-31 23:00:00', 0),
    ]:
        fixture = encounter('a', '2020-01-01 00:00:00', stop) + encounter('b', next_start, None)
        rows = case(fixture, '03_encounter_analytics.sql', 3)
        assert int(rows[0]['return_encounters_within_30_days']) == expected, rows
    print('OK : borne exacte de 30 jours, chevauchement et durée négative.')

    fixture = encounter('a', '2020-01-01', '2020-01-02', 80, 40) + encounter('b', '2020-03-01', None, 40000, 36000)
    rows = case(fixture, '03_encounter_analytics.sql', 12)
    assert rows[0]['weighted_coverage_rate_pct'] == '89.92', rows
    rows = case(encounter('a', '2020-01-01', None, 0, 0), '03_encounter_analytics.sql', 12)
    assert rows[0]['weighted_coverage_rate_pct'] == 'NULL', rows
    print('OK : couverture pondérée et coût total nul.')

    rows = case(fixture, '06_window_functions_cohorts.sql', 3)
    assert [int(r['encounter_count']) for r in rows] == [1, 0, 1], rows
    assert rows[1]['month_start'] == '2020-02-01' and rows[2]['previous_month_encounters'] == '0'
    print('OK : mois sans passage présent dans le calendrier.')

    fixture = encounter('a', '2020-01-01', None) + encounter('b', '2022-01-01', None)
    rows = case(fixture, '06_window_functions_cohorts.sql', 5)
    assert [(r['years_since_first'], r['active_patients']) for r in rows] == [('0', '1'), ('1', '0'), ('2', '1')], rows
    print('OK : année observée sans activité à zéro, années futures absentes.')

    fixture = "UPDATE patients SET BIRTHDATE='2020-01-02', DEATHDATE='2020-01-04';\n" + encounter('a', '2020-01-01', '2020-01-03') + encounter('b', '2020-01-05', '2020-01-06')
    rows = case(fixture, '05_data_quality_checks.sql', 13)
    assert list(rows[0].values()) == ['1', '1', '1'], rows
    print('OK : passages hors de la vie du patient détectés.')
    fixture = ''.join(encounter(str(i), f'2020-01-0{i} 00:00:00', f'2020-01-0{i} 0{i}:00:00') for i in range(1, 5))
    fixture += encounter('missing', '2020-01-06', None)
    rows = case(fixture, '07_portfolio_summary.sql', 1)
    assert rows[0]['encounter_count'] == '5' and rows[0]['valid_duration_count'] == '4', rows
    assert rows[0]['median_hours'] == '2.50' and rows[0]['average_hours'] == '2.50', rows
    assert rows[0]['total_claim_cost'] == '500.00', rows
    print('OK : médiane paire et dénominateurs distincts pour volumes, durées et coûts.')
    fixture = encounter('a','2020-01-01','2020-01-01 01:00:00') + encounter('b','2020-01-02','2020-01-02 02:00:00') + encounter('c','2020-01-03','2020-01-07 04:00:00')
    rows = case(fixture, '07_portfolio_summary.sql', 6)
    scenarios = {r['scenario']:r for r in rows}
    assert scenarios['all_recorded']['average_hours'] == '34.33', rows
    assert scenarios['all_recorded']['median_hours'] == '2.00', rows
    assert scenarios['without_over_24h']['encounter_count'] == '2', rows
    assert scenarios['without_over_24h']['average_hours'] == '1.50', rows
    print('OK : sensibilité aux durées longues, seuil explicite sans altérer la base.')
    print('Huit groupes de contrôles SQL réussis ; données source préservées.')


if __name__ == '__main__':
    command = sys.argv[1:]
    if not command:
        raise SystemExit('Usage : python scripts/check_sql.py mysql --batch --raw ... hospital_analytics')
    main(command)
