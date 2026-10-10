"""Rapprocher les lignes chargées et les sommes financières avec les CSV source."""
from decimal import Decimal
import sys
from prepare_maven import read_source
from check_sql import run_query

def main(command):
    tables, _ = read_source()
    for name, rows in tables.items():
        actual = run_query(command, f'SELECT COUNT(*) AS n FROM {name};')[0]
        assert int(actual['n']) == len(rows), (name, actual, len(rows))
    for table, column in [('encounters','TOTAL_CLAIM_COST'), ('encounters','PAYER_COVERAGE'), ('procedures','BASE_COST')]:
        expected = sum(Decimal(r[column]) for r in tables[table])
        actual = Decimal(run_query(command, f'SELECT SUM({column}) AS amount FROM {table};')[0]['amount'])
        assert actual == expected, (table,column,actual,expected)
    print('Import rapproché : cinq volumes et trois sommes financières exactes, sans perte de ligne.')

if __name__ == '__main__':
    main(sys.argv[1:])
