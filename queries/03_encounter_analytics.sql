-- ============================================================================
-- 03_encounter_analytics.sql
-- Encounter utilization, return visits, duration, timing, and payer coverage
-- ============================================================================

-- 1. Annual encounter activity
SELECT
    YEAR(START) AS year,
    COUNT(DISTINCT PATIENT) AS unique_patients,
    COUNT(*) AS total_encounters,
    ROUND(COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT PATIENT), 0), 2) AS encounters_per_patient
FROM encounters
GROUP BY YEAR(START)
ORDER BY year;

-- 2. Patients with more than one recorded encounter
-- This is repeat utilization, not a clinical readmission rate.
WITH patient_counts AS (
    SELECT PATIENT, COUNT(*) AS encounter_count
    FROM encounters
    GROUP BY PATIENT
)
SELECT
    COUNT(*) AS patients_with_encounters,
    SUM(encounter_count > 1) AS patients_with_multiple_encounters,
    ROUND(SUM(encounter_count > 1) * 100.0 / COUNT(*), 2) AS multiple_encounter_share_pct
FROM patient_counts;

-- 3. 30-day return-encounter proxy using the next recorded encounter
-- Not a validated clinical readmission metric.
WITH ordered_encounters AS (
    SELECT
        PATIENT,
        START,
        STOP,
        LEAD(START) OVER (PARTITION BY PATIENT ORDER BY START, Id) AS next_start
    FROM encounters
    WHERE STOP IS NOT NULL
),
return_intervals AS (
    SELECT
        PATIENT,
        TIMESTAMPDIFF(DAY, STOP, next_start) AS gap_days
    FROM ordered_encounters
    WHERE next_start IS NOT NULL
)
SELECT
    COUNT(*) AS return_encounters_within_30_days,
    COUNT(DISTINCT PATIENT) AS patients_with_return_within_30_days,
    ROUND(AVG(gap_days), 1) AS average_gap_days
FROM return_intervals
WHERE gap_days BETWEEN 0 AND 30;

-- 4. Encounter duration by class
SELECT
    ENCOUNTERCLASS AS encounter_class,
    COUNT(*) AS encounter_count,
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, START, STOP)) / 60.0, 2) AS average_hours,
    MIN(TIMESTAMPDIFF(MINUTE, START, STOP)) AS minimum_minutes,
    MAX(TIMESTAMPDIFF(MINUTE, START, STOP)) AS maximum_minutes
FROM encounters
WHERE STOP IS NOT NULL
  AND STOP >= START
GROUP BY ENCOUNTERCLASS
ORDER BY average_hours DESC;

-- 5. Encounter-duration distribution
WITH valid_durations AS (
    SELECT TIMESTAMPDIFF(MINUTE, START, STOP) AS duration_minutes
    FROM encounters
    WHERE STOP IS NOT NULL
      AND STOP >= START
)
SELECT
    CASE
        WHEN duration_minutes < 60 THEN '< 1 hour'
        WHEN duration_minutes <= 24 * 60 THEN '1-24 hours'
        WHEN duration_minutes <= 3 * 24 * 60 THEN '1-3 days'
        WHEN duration_minutes <= 7 * 24 * 60 THEN '3-7 days'
        WHEN duration_minutes <= 14 * 24 * 60 THEN '7-14 days'
        WHEN duration_minutes <= 30 * 24 * 60 THEN '14-30 days'
        ELSE '> 30 days'
    END AS duration_range,
    COUNT(*) AS encounter_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM valid_durations), 2) AS percentage
FROM valid_durations
GROUP BY duration_range
ORDER BY MIN(duration_minutes);

-- 6. Broad encounter grouping
SELECT
    CASE
        WHEN ENCOUNTERCLASS IN ('emergency', 'urgentcare') THEN 'Emergency / urgent care'
        WHEN ENCOUNTERCLASS IN ('ambulatory', 'outpatient', 'wellness') THEN 'Ambulatory / outpatient'
        WHEN ENCOUNTERCLASS = 'inpatient' THEN 'Inpatient'
        ELSE 'Other'
    END AS encounter_group,
    COUNT(*) AS encounter_count,
    ROUND(AVG(TOTAL_CLAIM_COST), 2) AS average_claim_cost,
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, START, STOP)) / 60.0, 2) AS average_duration_hours
FROM encounters
WHERE STOP IS NOT NULL
  AND STOP >= START
GROUP BY encounter_group
ORDER BY encounter_count DESC;

-- 7. Activity by day of week
SELECT
    DAYNAME(START) AS day_of_week,
    DAYOFWEEK(START) AS day_number,
    COUNT(*) AS encounter_count,
    ROUND(AVG(TOTAL_CLAIM_COST), 2) AS average_claim_cost
FROM encounters
GROUP BY DAYNAME(START), DAYOFWEEK(START)
ORDER BY day_number;

-- 8. Activity by month
SELECT
    MONTHNAME(START) AS month_name,
    MONTH(START) AS month_number,
    COUNT(*) AS encounter_count,
    ROUND(AVG(TOTAL_CLAIM_COST), 2) AS average_claim_cost
FROM encounters
GROUP BY MONTHNAME(START), MONTH(START)
ORDER BY month_number;

-- 9. Activity by quarter
SELECT
    QUARTER(START) AS quarter_number,
    COUNT(*) AS encounter_count,
    ROUND(AVG(TOTAL_CLAIM_COST), 2) AS average_claim_cost
FROM encounters
GROUP BY QUARTER(START)
ORDER BY quarter_number;

-- 10. Activity by four-hour time band
SELECT
    CASE
        WHEN HOUR(START) BETWEEN 0 AND 3 THEN '00-03'
        WHEN HOUR(START) BETWEEN 4 AND 7 THEN '04-07'
        WHEN HOUR(START) BETWEEN 8 AND 11 THEN '08-11'
        WHEN HOUR(START) BETWEEN 12 AND 15 THEN '12-15'
        WHEN HOUR(START) BETWEEN 16 AND 19 THEN '16-19'
        ELSE '20-23'
    END AS hour_band,
    COUNT(*) AS encounter_count
FROM encounters
GROUP BY hour_band
ORDER BY MIN(HOUR(START));

-- 11. Payer activity and weighted coverage rate
SELECT
    p.NAME AS payer_name,
    COUNT(e.Id) AS encounter_count,
    COUNT(DISTINCT e.PATIENT) AS unique_patients,
    ROUND(AVG(e.TOTAL_CLAIM_COST), 2) AS average_claim_cost,
    ROUND(AVG(e.PAYER_COVERAGE), 2) AS average_payer_coverage,
    ROUND(
        SUM(e.PAYER_COVERAGE) * 100.0 / NULLIF(SUM(e.TOTAL_CLAIM_COST), 0),
        2
    ) AS weighted_coverage_rate_pct
FROM encounters e
LEFT JOIN payers p
    ON e.PAYER = p.Id
GROUP BY p.Id, p.NAME
ORDER BY encounter_count DESC;

-- 12. Overall cost and payer coverage summary
SELECT
    COUNT(*) AS total_encounters,
    ROUND(AVG(BASE_ENCOUNTER_COST), 2) AS average_base_cost,
    ROUND(AVG(TOTAL_CLAIM_COST), 2) AS average_claim_cost,
    ROUND(AVG(PAYER_COVERAGE), 2) AS average_payer_coverage,
    ROUND(SUM(PAYER_COVERAGE) * 100.0 / NULLIF(SUM(TOTAL_CLAIM_COST), 0), 2) AS weighted_coverage_rate_pct
FROM encounters;

-- 13. Cost summary by encounter class
SELECT
    ENCOUNTERCLASS AS encounter_class,
    COUNT(*) AS encounter_count,
    ROUND(AVG(BASE_ENCOUNTER_COST), 2) AS average_base_cost,
    ROUND(AVG(TOTAL_CLAIM_COST), 2) AS average_claim_cost,
    ROUND(AVG(PAYER_COVERAGE), 2) AS average_payer_coverage,
    ROUND(AVG(TOTAL_CLAIM_COST - PAYER_COVERAGE), 2) AS average_uncovered_amount,
    ROUND(SUM(PAYER_COVERAGE) * 100.0 / NULLIF(SUM(TOTAL_CLAIM_COST), 0), 2) AS weighted_coverage_rate_pct
FROM encounters
GROUP BY ENCOUNTERCLASS
ORDER BY average_claim_cost DESC;
