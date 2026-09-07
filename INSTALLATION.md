# Installation

This project was written for **MySQL 8.0+**.

## 1. Download the dataset

Download **Hospital Patient Records** from Maven Analytics:

`https://mavenanalytics.io/data-playground/hospital-patient-records`

The dataset contains five CSV files:

- `organizations.csv`
- `payers.csv`
- `patients.csv`
- `encounters.csv`
- `procedures.csv`

The source data is not redistributed in this repository.

## 2. Create the database

From MySQL CLI:

```bash
mysql -u root -p
```

Then run:

```sql
SOURCE db/schema.sql;
```

If `SOURCE` is inconvenient on your platform, open `db/schema.sql` in MySQL Workbench and execute it.

## 3. Import the CSV files

### Option A — MySQL Workbench

Use **Table Data Import Wizard** and import the files in this order:

1. `organizations.csv`
2. `payers.csv`
3. `patients.csv`
4. `encounters.csv`
5. `procedures.csv`

The order matters because of foreign-key dependencies.

### Option B — `LOAD DATA LOCAL INFILE`

Copy `db/load_data.example.sql`, replace each placeholder path with the absolute path to your local CSV file, then execute it.

Your MySQL client/server may need local-file loading enabled:

```bash
mysql --local-infile=1 -u root -p
```

## 4. Verify row counts

```sql
USE hospital_analytics;

SELECT 'patients' AS table_name, COUNT(*) AS row_count FROM patients
UNION ALL
SELECT 'encounters', COUNT(*) FROM encounters
UNION ALL
SELECT 'procedures', COUNT(*) FROM procedures
UNION ALL
SELECT 'organizations', COUNT(*) FROM organizations
UNION ALL
SELECT 'payers', COUNT(*) FROM payers;
```

For the snapshot used in the original analysis, the expected counts were:

- 974 patients
- 27,891 encounters
- 47,701 procedures
- 1 organization
- 10 payers

## 5. Run data-quality checks

Run:

```text
queries/05_data_quality_checks.sql
```

Review any unexpected nulls, duplicate IDs, invalid date intervals, negative costs, or orphaned relationships before interpreting the analytical queries.

## 6. Run the analytics

Execute the remaining files in order:

```text
queries/01_data_exploration.sql
queries/02_patient_analytics.sql
queries/03_encounter_analytics.sql
queries/04_procedure_financial_analytics.sql
```
