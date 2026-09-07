-- ============================================================================
-- 04_procedure_financial_analytics.sql
-- Procedure volume, cost concentration, temporal trends, and reasons
-- ============================================================================

-- 1. Most frequent procedures
SELECT
    DESCRIPTION AS procedure_description,
    COUNT(*) AS procedure_count,
    ROUND(AVG(BASE_COST), 2) AS average_base_cost,
    ROUND(SUM(BASE_COST), 2) AS total_base_cost,
    COUNT(DISTINCT PATIENT) AS unique_patients
FROM procedures
GROUP BY DESCRIPTION
ORDER BY procedure_count DESC
LIMIT 15;

-- 2. Procedures with the highest average base cost
SELECT
    DESCRIPTION AS procedure_description,
    COUNT(*) AS procedure_count,
    ROUND(AVG(BASE_COST), 2) AS average_base_cost,
    ROUND(MAX(BASE_COST), 2) AS maximum_base_cost,
    ROUND(SUM(BASE_COST), 2) AS total_base_cost
FROM procedures
GROUP BY DESCRIPTION
HAVING COUNT(*) >= 2
ORDER BY average_base_cost DESC
LIMIT 15;

-- 3. Procedure-cost distribution
SELECT
    CASE
        WHEN BASE_COST < 100 THEN '< $100'
        WHEN BASE_COST < 500 THEN '$100-$499'
        WHEN BASE_COST < 1000 THEN '$500-$999'
        WHEN BASE_COST < 5000 THEN '$1,000-$4,999'
        WHEN BASE_COST < 10000 THEN '$5,000-$9,999'
        ELSE '$10,000+'
    END AS cost_range,
    COUNT(*) AS procedure_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM procedures), 2) AS percentage
FROM procedures
GROUP BY cost_range
ORDER BY MIN(BASE_COST);

-- 4. Patients with the highest procedure utilization
SELECT
    PATIENT AS patient_id,
    COUNT(*) AS procedure_count,
    ROUND(SUM(BASE_COST), 2) AS total_procedure_base_cost,
    ROUND(AVG(BASE_COST), 2) AS average_procedure_base_cost
FROM procedures
GROUP BY PATIENT
ORDER BY procedure_count DESC
LIMIT 15;

-- 5. Procedure-count distribution per patient
WITH patient_procedures AS (
    SELECT PATIENT, COUNT(*) AS procedure_count
    FROM procedures
    GROUP BY PATIENT
)
SELECT
    CASE
        WHEN procedure_count = 1 THEN '1'
        WHEN procedure_count BETWEEN 2 AND 5 THEN '2-5'
        WHEN procedure_count BETWEEN 6 AND 10 THEN '6-10'
        WHEN procedure_count BETWEEN 11 AND 20 THEN '11-20'
        ELSE '21+'
    END AS procedure_range,
    COUNT(*) AS patient_count
FROM patient_procedures
GROUP BY procedure_range
ORDER BY MIN(procedure_count);

-- 6. Quarterly procedure activity
SELECT
    QUARTER(START) AS quarter_number,
    COUNT(*) AS procedure_count,
    COUNT(DISTINCT PATIENT) AS unique_patients,
    ROUND(AVG(BASE_COST), 2) AS average_base_cost,
    ROUND(SUM(BASE_COST), 2) AS total_base_cost
FROM procedures
GROUP BY QUARTER(START)
ORDER BY quarter_number;

-- 7. Annual procedure activity
SELECT
    YEAR(START) AS year,
    COUNT(*) AS procedure_count,
    COUNT(DISTINCT PATIENT) AS unique_patients,
    ROUND(AVG(BASE_COST), 2) AS average_base_cost,
    ROUND(SUM(BASE_COST), 2) AS total_base_cost
FROM procedures
GROUP BY YEAR(START)
ORDER BY year;

-- 8. Most common documented procedure reasons
SELECT
    COALESCE(NULLIF(REASONDESCRIPTION, ''), 'Not documented') AS procedure_reason,
    COUNT(*) AS procedure_count,
    COUNT(DISTINCT PATIENT) AS unique_patients,
    ROUND(AVG(BASE_COST), 2) AS average_base_cost,
    ROUND(SUM(BASE_COST), 2) AS total_base_cost
FROM procedures
GROUP BY COALESCE(NULLIF(REASONDESCRIPTION, ''), 'Not documented')
ORDER BY procedure_count DESC
LIMIT 15;

-- 9. Procedure descriptions contributing the highest total base cost
SELECT
    DESCRIPTION AS procedure_description,
    COUNT(*) AS procedure_count,
    ROUND(SUM(BASE_COST), 2) AS total_base_cost,
    ROUND(
        SUM(BASE_COST) * 100.0 / NULLIF((SELECT SUM(BASE_COST) FROM procedures), 0),
        2
    ) AS share_of_total_procedure_cost_pct
FROM procedures
GROUP BY DESCRIPTION
ORDER BY total_base_cost DESC
LIMIT 15;
