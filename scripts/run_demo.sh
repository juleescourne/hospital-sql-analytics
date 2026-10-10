#!/usr/bin/env bash
# Rebuild the dedicated Maven analysis database and export all query results.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -v
python3 scripts/prepare_maven.py
if [[ "${1:-}" == "--local" ]]; then
  client=("${MYSQL_BIN:-mysql}" --local-infile=1 --batch --raw -u "${MYSQL_USER:-root}")
  if [[ -n "${MYSQL_SOCKET:-}" ]]; then
    client+=(--socket="$MYSQL_SOCKET")
  else
    client+=(-h "${MYSQL_HOST:-127.0.0.1}" -P "${MYSQL_PORT:-3306}")
  fi
else
  docker compose up -d --wait
  # LOAD DATA paths are generated on the host; use a loader with container paths.
  sed "s|$PWD/data/prepared/|/data/prepared/|g" db/load_maven.sql > db/load_maven_container.sql
  client=(docker compose exec -T -w / mysql mysql --local-infile=1 --batch --raw -uroot -phospital)
fi
# This dedicated database is recreated from the archived public source.
"${client[@]}" -e 'DROP DATABASE IF EXISTS hospital_analytics;'
"${client[@]}" < db/schema.sql
python3 scripts/check_sql.py "${client[@]}" hospital_analytics
if [[ "${1:-}" == "--local" ]]; then
  "${client[@]}" hospital_analytics < db/load_maven.sql
else
  "${client[@]}" hospital_analytics < db/load_maven_container.sql
fi
python3 scripts/check_source_import.py "${client[@]}" hospital_analytics
"${client[@]}" hospital_analytics -e 'ANALYZE TABLE encounters;' > /dev/null
mkdir -p results
"${client[@]}" hospital_analytics -e 'SELECT VERSION() AS mysql_version;' > results/environment.tsv
for query in queries/05_data_quality_checks.sql queries/01_data_exploration.sql queries/02_patient_analytics.sql queries/03_encounter_analytics.sql queries/04_procedure_financial_analytics.sql queries/06_window_functions_cohorts.sql queries/07_portfolio_summary.sql; do
  "${client[@]}" hospital_analytics < "$query" > "results/$(basename "${query%.sql}").tsv"
done
"${client[@]}" hospital_analytics -e 'EXPLAIN FORMAT=TREE SELECT PATIENT, START, LEAD(START) OVER (PARTITION BY PATIENT ORDER BY START, Id) AS next_start FROM encounters;' > results/explain.txt
python3 scripts/export_portfolio.py "${client[@]}" hospital_analytics
printf 'Seven SQL files and all regression checks succeeded. Results: results/\n'
