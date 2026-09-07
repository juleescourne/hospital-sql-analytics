-- ============================================================================
-- 05_data_quality_checks.sql
-- Data completeness, validity, duplicates, and referential-integrity checks
-- Run this file before interpreting analytical results.
-- ============================================================================

-- 1. Core row counts
SELECT 'patients' AS table_name, COUNT(*) AS row_count FROM patients
UNION ALL
SELECT 'encounters', COUNT(*) FROM encounters
UNION ALL
SELECT 'procedures', COUNT(*) FROM procedures
UNION ALL
SELECT 'organizations', COUNT(*) FROM organizations
UNION ALL
SELECT 'payers', COUNT(*) FROM payers;

-- 2. Patient-field completeness
SELECT
    SUM(BIRTHDATE IS NULL) AS missing_birthdate,
    SUM(GENDER IS NULL OR GENDER = '') AS missing_gender,
    SUM(RACE IS NULL OR RACE = '') AS missing_race,
    SUM(ETHNICITY IS NULL OR ETHNICITY = '') AS missing_ethnicity,
    SUM(CITY IS NULL OR CITY = '') AS missing_city
FROM patients;

-- 3. Encounter-field completeness
SELECT
    SUM(START IS NULL) AS missing_start,
    SUM(STOP IS NULL) AS missing_stop,
    SUM(PATIENT IS NULL OR PATIENT = '') AS missing_patient_id,
    SUM(ORGANIZATION IS NULL OR ORGANIZATION = '') AS missing_organization_id,
    SUM(PAYER IS NULL OR PAYER = '') AS missing_payer_id,
    SUM(TOTAL_CLAIM_COST IS NULL) AS missing_total_claim_cost,
    SUM(PAYER_COVERAGE IS NULL) AS missing_payer_coverage
FROM encounters;

-- 4. Procedure-field completeness
SELECT
    SUM(START IS NULL) AS missing_start,
    SUM(PATIENT IS NULL OR PATIENT = '') AS missing_patient_id,
    SUM(ENCOUNTER IS NULL OR ENCOUNTER = '') AS missing_encounter_id,
    SUM(DESCRIPTION IS NULL OR DESCRIPTION = '') AS missing_description,
    SUM(BASE_COST IS NULL) AS missing_base_cost
FROM procedures;

-- 5. Invalid temporal intervals
SELECT
    SUM(STOP IS NOT NULL AND STOP < START) AS encounters_with_negative_duration
FROM encounters;

SELECT
    SUM(STOP IS NOT NULL AND STOP < START) AS procedures_with_negative_duration
FROM procedures;

-- 6. Negative financial values
SELECT
    SUM(BASE_ENCOUNTER_COST < 0) AS negative_base_encounter_cost,
    SUM(TOTAL_CLAIM_COST < 0) AS negative_total_claim_cost,
    SUM(PAYER_COVERAGE < 0) AS negative_payer_coverage,
    SUM(PAYER_COVERAGE > TOTAL_CLAIM_COST) AS coverage_above_claim_cost
FROM encounters;

SELECT
    SUM(BASE_COST < 0) AS negative_procedure_base_cost
FROM procedures;

-- 7. Duplicate primary identifiers
SELECT Id, COUNT(*) AS duplicate_count
FROM patients
GROUP BY Id
HAVING COUNT(*) > 1;

SELECT Id, COUNT(*) AS duplicate_count
FROM encounters
GROUP BY Id
HAVING COUNT(*) > 1;

-- 8. Potential duplicate procedure rows
-- The source procedure table does not expose a dedicated procedure primary key.
SELECT
    PATIENT,
    ENCOUNTER,
    START,
    CODE,
    COUNT(*) AS duplicate_count
FROM procedures
GROUP BY PATIENT, ENCOUNTER, START, CODE
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 9. Orphaned encounter relationships
SELECT COUNT(*) AS encounters_without_patient
FROM encounters e
LEFT JOIN patients p ON e.PATIENT = p.Id
WHERE p.Id IS NULL;

SELECT COUNT(*) AS encounters_without_organization
FROM encounters e
LEFT JOIN organizations o ON e.ORGANIZATION = o.Id
WHERE o.Id IS NULL;

SELECT COUNT(*) AS encounters_without_payer
FROM encounters e
LEFT JOIN payers p ON e.PAYER = p.Id
WHERE e.PAYER IS NOT NULL
  AND p.Id IS NULL;

-- 10. Orphaned procedure relationships
SELECT COUNT(*) AS procedures_without_patient
FROM procedures pr
LEFT JOIN patients p ON pr.PATIENT = p.Id
WHERE p.Id IS NULL;

SELECT COUNT(*) AS procedures_without_encounter
FROM procedures pr
LEFT JOIN encounters e ON pr.ENCOUNTER = e.Id
WHERE e.Id IS NULL;

-- 11. Procedure-patient mismatch with parent encounter
SELECT COUNT(*) AS procedure_encounter_patient_mismatches
FROM procedures pr
JOIN encounters e ON pr.ENCOUNTER = e.Id
WHERE pr.PATIENT <> e.PATIENT;

-- 12. Dataset date range sanity check
SELECT
    MIN(START) AS earliest_encounter_start,
    MAX(START) AS latest_encounter_start,
    MIN(STOP) AS earliest_encounter_stop,
    MAX(STOP) AS latest_encounter_stop
FROM encounters;
