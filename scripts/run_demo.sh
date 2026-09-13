#!/usr/bin/env bash
# Rebuild the dedicated synthetic demo database and export all query results.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--local" ]]; then
  client=("${MYSQL_BIN:-mysql}" --local-infile=1 --batch --raw -u "${MYSQL_USER:-root}")
  if [[ -n "${MYSQL_SOCKET:-}" ]]; then
    client+=(--socket="$MYSQL_SOCKET")
  else
    client+=(-h "${MYSQL_HOST:-127.0.0.1}" -P "${MYSQL_PORT:-3306}")
  fi
else
  docker compose up -d --wait
  client=(docker compose exec -T -w / mysql mysql --local-infile=1 --batch --raw -uroot -phospital)
fi
python3 scripts/generate_sample_data.py
# This database is reserved for generated data. No external database is targeted.
"${client[@]}" -e 'DROP DATABASE IF EXISTS hospital_analytics;'
"${client[@]}" < db/schema.sql
"${client[@]}" hospital_analytics < db/load_sample_data.sql
mkdir -p results
"${client[@]}" hospital_analytics -e 'SELECT VERSION() AS mysql_version;' > results/environment.tsv
for query in queries/05_data_quality_checks.sql queries/01_data_exploration.sql queries/02_patient_analytics.sql queries/03_encounter_analytics.sql queries/04_procedure_financial_analytics.sql queries/06_window_functions_cohorts.sql; do
  "${client[@]}" hospital_analytics < "$query" > "results/$(basename "${query%.sql}").tsv"
done
"${client[@]}" hospital_analytics -e 'EXPLAIN FORMAT=TREE SELECT PATIENT, START, LEAD(START) OVER (PARTITION BY PATIENT ORDER BY START, Id) AS next_start FROM encounters;' > results/explain.txt
printf 'All six SQL files executed successfully. Results: results/\n'
