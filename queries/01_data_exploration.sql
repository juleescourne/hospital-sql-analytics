-- ============================================================================
-- 01_data_exploration.sql
-- High-level dataset profiling and descriptive metrics
-- ============================================================================

-- 1. Row counts by table
SELECT 'patients' AS table_name, COUNT(*) AS row_count FROM patients
UNION ALL
SELECT 'encounters', COUNT(*) FROM encounters
UNION ALL
SELECT 'procedures', COUNT(*) FROM procedures
UNION ALL
SELECT 'organizations', COUNT(*) FROM organizations
UNION ALL
SELECT 'payers', COUNT(*) FROM payers
ORDER BY row_count DESC;

-- 2. Dataset time coverage
SELECT
    MIN(START) AS first_encounter,
    MAX(START) AS last_encounter,
    TIMESTAMPDIFF(YEAR, MIN(START), MAX(START)) AS years_covered,
    TIMESTAMPDIFF(MONTH, MIN(START), MAX(START)) AS months_covered
FROM encounters;

-- 3. Patient distribution by sex
SELECT
    COALESCE(GENDER, 'Unknown') AS gender,
    COUNT(*) AS patient_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM patients), 1) AS percentage
FROM patients
GROUP BY COALESCE(GENDER, 'Unknown')
ORDER BY patient_count DESC;

-- 4. Patient age bands at the end of the dataset period
WITH dataset_end AS (
    SELECT DATE(MAX(START)) AS as_of_date
    FROM encounters
),
patient_ages AS (
    SELECT
        p.Id,
        TIMESTAMPDIFF(YEAR, p.BIRTHDATE, d.as_of_date) AS age
    FROM patients p
    CROSS JOIN dataset_end d
    WHERE p.BIRTHDATE IS NOT NULL
)
SELECT
    CASE
        WHEN age < 18 THEN '0-17'
        WHEN age BETWEEN 18 AND 29 THEN '18-29'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        WHEN age BETWEEN 50 AND 59 THEN '50-59'
        WHEN age BETWEEN 60 AND 69 THEN '60-69'
        WHEN age BETWEEN 70 AND 79 THEN '70-79'
        ELSE '80+'
    END AS age_group,
    COUNT(*) AS patient_count,
    ROUND(AVG(age), 1) AS average_age
FROM patient_ages
GROUP BY age_group
ORDER BY MIN(age);

-- 5. Cities with the largest patient populations
SELECT
    CITY AS city,
    STATE AS state,
    COUNT(*) AS patient_count
FROM patients
GROUP BY CITY, STATE
ORDER BY patient_count DESC
LIMIT 10;

-- 6. Encounter-class distribution and average claim cost
SELECT
    ENCOUNTERCLASS AS encounter_class,
    COUNT(*) AS encounter_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM encounters), 1) AS share_pct,
    ROUND(AVG(TOTAL_CLAIM_COST), 2) AS average_claim_cost
FROM encounters
GROUP BY ENCOUNTERCLASS
ORDER BY encounter_count DESC;

-- 7. Annual encounter activity
SELECT
    YEAR(START) AS year,
    COUNT(*) AS encounter_count,
    COUNT(DISTINCT PATIENT) AS unique_patients,
    ROUND(COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT PATIENT), 0), 2) AS encounters_per_patient
FROM encounters
GROUP BY YEAR(START)
ORDER BY year;

-- 8. Executive summary metrics using the dataset end date for age calculation
WITH dataset_end AS (
    SELECT DATE(MAX(START)) AS as_of_date
    FROM encounters
)
SELECT
    (SELECT COUNT(*) FROM patients) AS total_patients,
    (SELECT COUNT(*) FROM encounters) AS total_encounters,
    (SELECT COUNT(*) FROM procedures) AS total_procedures,
    (
        SELECT ROUND(AVG(TIMESTAMPDIFF(YEAR, p.BIRTHDATE, d.as_of_date)), 1)
        FROM patients p
        CROSS JOIN dataset_end d
        WHERE p.BIRTHDATE IS NOT NULL
    ) AS average_patient_age,
    (SELECT ROUND(AVG(TOTAL_CLAIM_COST), 2) FROM encounters) AS average_claim_cost,
    (SELECT ROUND(SUM(TOTAL_CLAIM_COST), 2) FROM encounters) AS total_claim_amount,
    (SELECT COUNT(*) FROM patients WHERE DEATHDATE IS NOT NULL) AS patients_with_death_date;
