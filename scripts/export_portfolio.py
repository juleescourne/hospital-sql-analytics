"""Exporter trois tableaux métier depuis MySQL, pour la synthèse et le portfolio."""
import csv
import hashlib
import json
from pathlib import Path
import re
import sys
from check_sql import query_section, run_query

ROOT = Path(__file__).resolve().parents[1]


def typed(row):
    result = {}
    for key, value in row.items():
        if value == 'NULL':
            result[key] = None
        elif re.fullmatch(r'-?\d+', value):
            result[key] = int(value)
        elif re.fullmatch(r'-?\d+\.\d+', value):
            result[key] = float(value)
        else:
            result[key] = value
    return result


def main(command):
    results = ROOT / 'results'
    results.mkdir(exist_ok=True)
    data = {'source': 'Données synthétiques, graine 42, 400 patients demandés',
            'currency': 'USD',
            'query_file': 'queries/07_portfolio_summary.sql',
            'query_sha256': hashlib.sha256((ROOT / 'queries/07_portfolio_summary.sql').read_bytes()).hexdigest()}
    for index, name in enumerate(['activity', 'coverage', 'quality', 'overview'], 1):
        rows = run_query(command, query_section('07_portfolio_summary.sql', index))
        if not rows:
            raise ValueError('Résultat vide : ' + name)
        with (results / (name + '.csv')).open('w', encoding='utf-8-sig', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=rows[0], delimiter=';', lineterminator='\n')
            writer.writeheader()
            writer.writerows(rows)
        data[name] = [typed(row) for row in rows]
    data['overview'] = data['overview'][0]
    # Rapprochements entre les trois restitutions et le bilan global.
    overview = data['overview']
    assert sum(r['encounter_count'] for r in data['activity']) == overview['encounters']
    assert sum(r['encounter_count'] for r in data['coverage']) == overview['encounters']
    assert sum(r['valid_duration_count'] for r in data['activity']) == overview['valid_durations']
    for rows in [data['activity'], data['coverage']]:
        assert abs(sum(r['total_claim_cost'] for r in rows) - overview['total_claim_cost']) < 0.02
    (results / 'portfolio.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    explain = results / 'explain.txt'
    if explain.exists():
        explain.write_text('\n'.join(line.rstrip() for line in explain.read_text().splitlines()).rstrip() + '\n')
    print('Exports métier MySQL rapprochés : quatre CSV et portfolio.json.')


if __name__ == '__main__':
    if not sys.argv[1:]:
        raise SystemExit('Usage : python scripts/export_portfolio.py mysql --batch --raw ... hospital_analytics')
    main(sys.argv[1:])
