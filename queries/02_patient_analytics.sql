-- ============================================================================
-- 02_patient_analytics.sql
-- Patient demographics and utilization patterns
-- ============================================================================

-- 1. Age-group distribution by sex at the end of the dataset period
-- Age is measured at the end of the observation window for living patients, and at the
-- recorded date of death otherwise. Using the window end for everyone would age deceased
-- patients past the point where they could be observed: a patient who died in 2013 would
-- be reported with their 2022 age.
WITH dataset_end AS (
    SELECT DATE(MAX(START)) AS as_of_date
    FROM encounters
),
patient_ages AS (
    SELECT
        p.Id,
        p.GENDER,
        TIMESTAMPDIFF(
            YEAR,
            p.BIRTHDATE,
            LEAST(COALESCE(p.DEATHDATE, d.as_of_date), d.as_of_date)
        ) AS age
    FROM patients p
    CROSS JOIN dataset_end d
    WHERE p.BIRTHDATE IS NOT NULL
)
SELECT
    COALESCE(GENDER, 'Unknown') AS gender,
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
    COUNT(*) AS patient_count
FROM patient_ages
GROUP BY gender, age_group
ORDER BY gender, MIN(age);

-- 2. Ethnicity distribution
SELECT
    COALESCE(ETHNICITY, 'Unknown') AS ethnicity,
    COUNT(*) AS patient_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM patients), 2) AS percentage
FROM patients
GROUP BY COALESCE(ETHNICITY, 'Unknown')
ORDER BY patient_count DESC;

-- 3. Race and sex distribution
SELECT
    COALESCE(RACE, 'Unknown') AS race,
    COALESCE(GENDER, 'Unknown') AS gender,
    COUNT(*) AS patient_count
FROM patients
GROUP BY race, gender
ORDER BY race, gender;

-- 4. Descriptive death-date coverage
-- This is a dataset description, not a clinical mortality benchmark.
SELECT
    COUNT(*) AS total_patients,
    SUM(CASE WHEN DEATHDATE IS NOT NULL THEN 1 ELSE 0 END) AS patients_with_death_date,
    ROUND(
        SUM(CASE WHEN DEATHDATE IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        2
    ) AS share_with_death_date_pct
FROM patients;

-- 5. Age at death among records with a death date
SELECT
    ROUND(AVG(TIMESTAMPDIFF(YEAR, BIRTHDATE, DEATHDATE)), 2) AS average_age_at_death,
    MIN(TIMESTAMPDIFF(YEAR, BIRTHDATE, DEATHDATE)) AS minimum_age_at_death,
    MAX(TIMESTAMPDIFF(YEAR, BIRTHDATE, DEATHDATE)) AS maximum_age_at_death
FROM patients
WHERE BIRTHDATE IS NOT NULL
  AND DEATHDATE IS NOT NULL;

-- 6. Geographic distribution
SELECT
    CITY AS city,
    STATE AS state,
    COUNT(*) AS patient_count
FROM patients
GROUP BY CITY, STATE
ORDER BY patient_count DESC
LIMIT 15;

SELECT
    COUNTY AS county,
    STATE AS state,
    COUNT(*) AS patient_count
FROM patients
GROUP BY COUNTY, STATE
ORDER BY patient_count DESC
LIMIT 20;

-- 7. Highest-utilization patients, using identifiers rather than names
WITH dataset_end AS (
    SELECT DATE(MAX(START)) AS as_of_date
    FROM encounters
)
SELECT
    p.Id AS patient_id,
    TIMESTAMPDIFF(YEAR, p.BIRTHDATE, d.as_of_date) AS age,
    COUNT(e.Id) AS encounter_count,
    DATE(MIN(e.START)) AS first_encounter,
    DATE(MAX(e.START)) AS last_encounter,
    TIMESTAMPDIFF(MONTH, MIN(e.START), MAX(e.START)) AS months_between_first_and_last
FROM patients p
JOIN encounters e
    ON p.Id = e.PATIENT
CROSS JOIN dataset_end d
GROUP BY p.Id, p.BIRTHDATE, d.as_of_date
ORDER BY encounter_count DESC
LIMIT 15;

-- 8. Encounter-frequency distribution per patient
WITH patient_encounters AS (
    SELECT PATIENT, COUNT(*) AS encounter_count
    FROM encounters
    GROUP BY PATIENT
)
SELECT
    CASE
        WHEN encounter_count = 1 THEN '1'
        WHEN encounter_count BETWEEN 2 AND 10 THEN '2-10'
        WHEN encounter_count BETWEEN 11 AND 20 THEN '11-20'
        WHEN encounter_count BETWEEN 21 AND 50 THEN '21-50'
        ELSE '51+'
    END AS encounter_range,
    COUNT(*) AS patient_count
FROM patient_encounters
GROUP BY encounter_range
ORDER BY MIN(encounter_count);

-- 9. Encounter-frequency summary
SELECT
    ROUND(AVG(encounter_count), 2) AS average_encounters_per_patient,
    MIN(encounter_count) AS minimum_encounters,
    MAX(encounter_count) AS maximum_encounters
FROM (
    SELECT PATIENT, COUNT(*) AS encounter_count
    FROM encounters
    GROUP BY PATIENT
) patient_encounters;

-- 10. Marital-status profile
WITH dataset_end AS (
    SELECT DATE(MAX(START)) AS as_of_date
    FROM encounters
)
SELECT
    COALESCE(p.MARITAL, 'Unknown') AS marital_status,
    COUNT(*) AS patient_count,
    ROUND(AVG(TIMESTAMPDIFF(YEAR, p.BIRTHDATE, d.as_of_date)), 2) AS average_age,
    SUM(CASE WHEN p.DEATHDATE IS NOT NULL THEN 1 ELSE 0 END) AS patients_with_death_date
FROM patients p
CROSS JOIN dataset_end d
WHERE p.BIRTHDATE IS NOT NULL
GROUP BY COALESCE(p.MARITAL, 'Unknown')
ORDER BY patient_count DESC;
