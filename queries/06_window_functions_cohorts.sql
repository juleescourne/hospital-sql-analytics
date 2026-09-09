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
            ORDER BY total_base_cost DESC
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


-- 3. Monthly activity: running total, month-over-month change, 3-month moving average
-- SUM() OVER (ORDER BY ... ) with the default frame gives the cumulative total.
-- LAG compares each month with the previous one.
WITH monthly AS (
    SELECT
        DATE_FORMAT(START, '%Y-%m-01')      AS month_start,
        COUNT(*)                            AS encounter_count,
        ROUND(SUM(TOTAL_CLAIM_COST), 2)     AS monthly_claim_cost
    FROM encounters
    GROUP BY DATE_FORMAT(START, '%Y-%m-01')
)
SELECT
    month_start,
    encounter_count,
    monthly_claim_cost,
    SUM(monthly_claim_cost) OVER (
        ORDER BY month_start
    )                                                   AS cumulative_claim_cost,
    LAG(encounter_count) OVER (
        ORDER BY month_start
    )                                                   AS previous_month_encounters,
    encounter_count - LAG(encounter_count) OVER (
        ORDER BY month_start
    )                                                   AS encounter_change,
    ROUND(
        AVG(encounter_count) OVER (
            ORDER BY month_start
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        1
    )                                                   AS moving_avg_3_months
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
        NTILE(4) OVER (ORDER BY total_claim_cost) AS spend_quartile
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
WITH first_encounter AS (
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
SELECT
    c.cohort_year,
    s.cohort_patients,
    c.years_since_first,
    c.active_patients,
    ROUND(c.active_patients * 100.0 / NULLIF(s.cohort_patients, 0), 1) AS retention_pct
FROM cohort_activity c
JOIN cohort_size s ON s.cohort_year = c.cohort_year
WHERE c.years_since_first BETWEEN 0 AND 5
ORDER BY c.cohort_year, c.years_since_first;


-- 6. Gap between consecutive encounters, per patient
-- LAG on the previous STOP gives each patient's inter-encounter gap. PERCENT_RANK
-- positions each gap within the overall distribution, which is more informative than
-- an average when the distribution is heavily skewed.
WITH ordered_encounters AS (
    SELECT
        PATIENT,
        Id                                          AS encounter_id,
        START,
        LAG(STOP) OVER (
            PARTITION BY PATIENT
            ORDER BY START, Id
        )                                           AS previous_stop
    FROM encounters
    WHERE STOP IS NOT NULL
),
gaps AS (
    SELECT
        PATIENT,
        encounter_id,
        TIMESTAMPDIFF(DAY, previous_stop, START) AS gap_days
    FROM ordered_encounters
    WHERE previous_stop IS NOT NULL
)
SELECT
    CASE
        WHEN gap_days <= 7   THEN '0-7 days'
        WHEN gap_days <= 30  THEN '8-30 days'
        WHEN gap_days <= 90  THEN '31-90 days'
        WHEN gap_days <= 365 THEN '91-365 days'
        ELSE '> 365 days'
    END                                     AS gap_bucket,
    COUNT(*)                                AS encounter_count,
    ROUND(AVG(gap_days), 1)                 AS average_gap_days,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    )                                       AS share_pct
FROM gaps
WHERE gap_days >= 0
GROUP BY gap_bucket
ORDER BY MIN(gap_days);
