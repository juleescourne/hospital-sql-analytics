-- ============================================================================
-- 06_window_functions_cohorts.sql
-- Ranking, running totals, moving averages, quartiles and cohort retention
-- Requires MySQL 8.0+ (window functions).
-- ============================================================================

-- 1. Most expensive procedures within each encounter class
-- ROW_NUMBER gives a strict top-N per group; RANK would keep ties, which is not
-- what we want here since we only display five rows per class.
WITH procedure_costs AS (
    SELECT
        e.ENCOUNTERCLASS                AS encounter_class,
        pr.DESCRIPTION                  AS procedure_description,
        COUNT(*)                        AS procedure_count,
        ROUND(AVG(pr.BASE_COST), 2)     AS average_base_cost,
        ROUND(SUM(pr.BASE_COST), 2)     AS total_base_cost
    FROM procedures pr
    JOIN encounters e ON pr.ENCOUNTER = e.Id
    GROUP BY e.ENCOUNTERCLASS, pr.DESCRIPTION
),
ranked AS (
    SELECT
        procedure_costs.*,
        ROW_NUMBER() OVER (
            PARTITION BY encounter_class
            ORDER BY total_base_cost DESC, procedure_description
        ) AS cost_rank
    FROM procedure_costs
)
SELECT
    encounter_class,
    cost_rank,
    procedure_description,
    procedure_count,
    average_base_cost,
    total_base_cost
FROM ranked
WHERE cost_rank <= 5
ORDER BY encounter_class, cost_rank;


-- 2. Payers ranked by total claim volume, with their share of the total
-- DENSE_RANK keeps consecutive ranks when two payers tie.
SELECT
    p.NAME                                          AS payer_name,
    COUNT(e.Id)                                     AS encounter_count,
    ROUND(SUM(e.TOTAL_CLAIM_COST), 2)               AS total_claim_cost,
    DENSE_RANK() OVER (
        ORDER BY SUM(e.TOTAL_CLAIM_COST) DESC
    )                                               AS claim_rank,
    ROUND(
        SUM(e.TOTAL_CLAIM_COST) * 100.0
        / SUM(SUM(e.TOTAL_CLAIM_COST)) OVER (),
        2
    )                                               AS share_of_total_pct
FROM encounters e
LEFT JOIN payers p ON e.PAYER = p.Id
GROUP BY p.Id, p.NAME
ORDER BY claim_rank;


-- 3. Monthly activity, including zero-activity months within the observed window.
-- A row-based moving average needs a calendar so that three rows mean three months.
WITH RECURSIVE calendar AS (
    SELECT CAST(DATE_FORMAT(MIN(START), '%Y-%m-01') AS DATE) AS month_start,
           CAST(DATE_FORMAT(MAX(START), '%Y-%m-01') AS DATE) AS last_month
    FROM encounters
    HAVING COUNT(*) > 0
    UNION ALL
    SELECT DATE_ADD(month_start, INTERVAL 1 MONTH), last_month
    FROM calendar
    WHERE month_start < last_month
),
counts AS (
    SELECT CAST(DATE_FORMAT(START, '%Y-%m-01') AS DATE) AS month_start,
           COUNT(*) AS encounter_count, SUM(TOTAL_CLAIM_COST) AS monthly_claim_cost
    FROM encounters
    GROUP BY CAST(DATE_FORMAT(START, '%Y-%m-01') AS DATE)
),
monthly AS (
    SELECT c.month_start, COALESCE(n.encounter_count, 0) AS encounter_count,
           COALESCE(n.monthly_claim_cost, 0) AS monthly_claim_cost
    FROM calendar c LEFT JOIN counts n ON n.month_start = c.month_start
)
SELECT month_start, encounter_count, monthly_claim_cost,
       SUM(monthly_claim_cost) OVER (ORDER BY month_start) AS cumulative_claim_cost,
       LAG(encounter_count) OVER (ORDER BY month_start) AS previous_month_encounters,
       encounter_count - LAG(encounter_count) OVER (ORDER BY month_start) AS encounter_change,
       ROUND(AVG(encounter_count) OVER (
           ORDER BY month_start ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
       ), 1) AS moving_avg_3_months
FROM monthly
ORDER BY month_start;

-- 4. Patient spend quartiles
-- NTILE(4) splits patients into four equal-sized groups ordered by total claim cost.
-- Useful to check how concentrated spending is across the population.
WITH patient_spend AS (
    SELECT
        PATIENT                             AS patient_id,
        COUNT(*)                            AS encounter_count,
        ROUND(SUM(TOTAL_CLAIM_COST), 2)     AS total_claim_cost
    FROM encounters
    GROUP BY PATIENT
),
quartiles AS (
    SELECT
        patient_spend.*,
        NTILE(4) OVER (ORDER BY total_claim_cost, patient_id) AS spend_quartile
    FROM patient_spend
)
SELECT
    spend_quartile,
    COUNT(*)                                    AS patient_count,
    ROUND(MIN(total_claim_cost), 2)             AS min_spend,
    ROUND(MAX(total_claim_cost), 2)             AS max_spend,
    ROUND(AVG(encounter_count), 1)              AS avg_encounters,
    ROUND(SUM(total_claim_cost), 2)             AS quartile_total,
    ROUND(
        SUM(total_claim_cost) * 100.0
        / SUM(SUM(total_claim_cost)) OVER (),
        2
    )                                           AS share_of_total_pct
FROM quartiles
GROUP BY spend_quartile
ORDER BY spend_quartile;


-- 5. Cohort retention by year of first encounter
-- Each patient belongs to the cohort of the year they were first seen. We then measure
-- how many are still active N years later. This is descriptive retention on recorded
-- activity only: a patient absent from the data may have moved, recovered or died, so
-- this is not a measure of care continuity.
WITH year_offsets AS (
    SELECT 0 AS years_since_first UNION ALL SELECT 1 UNION ALL SELECT 2
    UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
),
first_encounter AS (
    SELECT
        PATIENT             AS patient_id,
        MIN(YEAR(START))    AS cohort_year
    FROM encounters
    GROUP BY PATIENT
),
activity AS (
    SELECT DISTINCT
        e.PATIENT           AS patient_id,
        YEAR(e.START)       AS activity_year
    FROM encounters e
),
cohort_activity AS (
    SELECT
        f.cohort_year,
        a.activity_year - f.cohort_year AS years_since_first,
        COUNT(DISTINCT a.patient_id)    AS active_patients
    FROM first_encounter f
    JOIN activity a ON a.patient_id = f.patient_id
    GROUP BY f.cohort_year, a.activity_year - f.cohort_year
),
cohort_size AS (
    SELECT cohort_year, COUNT(*) AS cohort_patients
    FROM first_encounter
    GROUP BY cohort_year
)
SELECT s.cohort_year, s.cohort_patients, y.years_since_first,
       COALESCE(c.active_patients, 0) AS active_patients,
       ROUND(COALESCE(c.active_patients, 0) * 100.0 / s.cohort_patients, 1) AS retention_pct
FROM cohort_size s
CROSS JOIN year_offsets y
LEFT JOIN cohort_activity c ON c.cohort_year = s.cohort_year
    AND c.years_since_first = y.years_since_first
WHERE s.cohort_year + y.years_since_first <= (SELECT MAX(YEAR(START)) FROM encounters)
ORDER BY s.cohort_year, y.years_since_first;

-- 6. Gap from the immediately preceding encounter, measured in complete seconds.
-- Keep missing STOP rows in the sequence; do not jump over an unknown interval.
WITH ordered_encounters AS (
    SELECT PATIENT, Id AS encounter_id, START,
           LAG(START) OVER (PARTITION BY PATIENT ORDER BY START, Id) AS previous_start,
           LAG(STOP) OVER (PARTITION BY PATIENT ORDER BY START, Id) AS previous_stop
    FROM encounters
),
gaps AS (
    SELECT TIMESTAMPDIFF(SECOND, previous_stop, START) / 86400.0 AS gap_days
    FROM ordered_encounters
    WHERE previous_stop >= previous_start AND START >= previous_stop
)
SELECT CASE
           WHEN gap_days <= 7 THEN '0-7 days'
           WHEN gap_days <= 30 THEN '>7-30 days'
           WHEN gap_days <= 90 THEN '>30-90 days'
           WHEN gap_days <= 365 THEN '>90-365 days'
           ELSE '>365 days'
       END AS gap_bucket,
       COUNT(*) AS encounter_count,
       ROUND(AVG(gap_days), 1) AS average_gap_days,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM gaps
GROUP BY gap_bucket
ORDER BY MIN(gap_days);
