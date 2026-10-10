-- 1. Volume and duration by encounter class: distinguish total and usable rows.
WITH ranked_durations AS (
    SELECT ENCOUNTERCLASS,
           TIMESTAMPDIFF(SECOND, START, STOP) / 3600.0 AS hours,
           ROW_NUMBER() OVER (PARTITION BY ENCOUNTERCLASS ORDER BY TIMESTAMPDIFF(SECOND, START, STOP), Id) AS rn,
           COUNT(*) OVER (PARTITION BY ENCOUNTERCLASS) AS n
    FROM encounters
    WHERE STOP IS NOT NULL AND STOP >= START
),
durations AS (
    SELECT ENCOUNTERCLASS, COUNT(*) AS valid_duration_count,
           ROUND(AVG(hours), 2) AS average_hours,
           ROUND(MAX(hours), 2) AS maximum_hours,
           SUM(hours > 24) AS duration_over_24h_count,
           ROUND(AVG(CASE WHEN rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2)) THEN hours END), 2) AS median_hours
    FROM ranked_durations GROUP BY ENCOUNTERCLASS
),
volumes AS (
    SELECT ENCOUNTERCLASS, COUNT(*) AS encounter_count,
           ROUND(SUM(TOTAL_CLAIM_COST), 2) AS total_claim_cost
    FROM encounters GROUP BY ENCOUNTERCLASS
)
SELECT v.ENCOUNTERCLASS AS encounter_class, v.encounter_count,
       ROUND(v.encounter_count * 100.0 / SUM(v.encounter_count) OVER (), 2) AS volume_share_pct,
       v.total_claim_cost,
       ROUND(v.total_claim_cost * 100.0 / SUM(v.total_claim_cost) OVER (), 2) AS cost_share_pct,
       COALESCE(d.valid_duration_count, 0) AS valid_duration_count,
       d.average_hours, d.median_hours, d.maximum_hours, d.duration_over_24h_count
FROM volumes v LEFT JOIN durations d ON d.ENCOUNTERCLASS = v.ENCOUNTERCLASS
ORDER BY v.encounter_count DESC, v.ENCOUNTERCLASS;

-- 2. Payer coverage: all encounters retained, including unknown payer identifiers.
SELECT COALESCE(p.NAME, 'Payeur non renseigné') AS payer_name,
       COUNT(*) AS encounter_count,
       ROUND(SUM(e.TOTAL_CLAIM_COST), 2) AS total_claim_cost,
       ROUND(SUM(e.PAYER_COVERAGE), 2) AS covered_amount,
       ROUND(SUM(e.TOTAL_CLAIM_COST - e.PAYER_COVERAGE), 2) AS uncovered_amount,
       ROUND(100.0 * SUM(e.PAYER_COVERAGE) / NULLIF(SUM(e.TOTAL_CLAIM_COST), 0), 2) AS weighted_coverage_pct
FROM encounters e LEFT JOIN payers p ON e.PAYER = p.Id
GROUP BY p.Id, p.NAME
ORDER BY encounter_count DESC, payer_name;

-- 3. Quality findings: overlapping flags, each with its own interpretation.
SELECT 'missing_stop' AS metric, COUNT(*) AS affected,
       (SELECT COUNT(*) FROM encounters) AS denominator
FROM encounters WHERE STOP IS NULL
UNION ALL
SELECT 'negative_duration', COUNT(*), (SELECT COUNT(*) FROM encounters)
FROM encounters WHERE STOP < START
UNION ALL
SELECT 'zero_duration', COUNT(*), (SELECT COUNT(*) FROM encounters)
FROM encounters WHERE STOP = START
UNION ALL
SELECT 'missing_payer', COUNT(*), (SELECT COUNT(*) FROM encounters)
FROM encounters WHERE PAYER IS NULL
UNION ALL
SELECT 'before_birth', COUNT(*), (SELECT COUNT(*) FROM encounters)
FROM encounters e JOIN patients p ON p.Id = e.PATIENT WHERE DATE(e.START) < p.BIRTHDATE
UNION ALL
SELECT 'after_death', COUNT(*), (SELECT COUNT(*) FROM encounters)
FROM encounters e JOIN patients p ON p.Id = e.PATIENT
WHERE p.DEATHDATE IS NOT NULL AND (DATE(e.START) > p.DEATHDATE OR DATE(e.STOP) > p.DEATHDATE)
UNION ALL
SELECT 'procedure_patient_mismatch', COUNT(*), (SELECT COUNT(*) FROM procedures)
FROM procedures pr JOIN encounters e ON e.Id = pr.ENCOUNTER WHERE pr.PATIENT <> e.PATIENT
UNION ALL
SELECT 'ambulatory_outpatient_over_24h', COUNT(*),
       (SELECT COUNT(*) FROM encounters WHERE ENCOUNTERCLASS IN ('ambulatory', 'outpatient'))
FROM encounters WHERE ENCOUNTERCLASS IN ('ambulatory', 'outpatient')
AND STOP > DATE_ADD(START, INTERVAL 24 HOUR);

-- 4. Overview, with cost and duration denominators kept separate.
SELECT (SELECT COUNT(*) FROM patients) AS patients,
       COUNT(*) AS encounters,
       (SELECT COUNT(*) FROM procedures) AS procedures,
       MIN(START) AS first_encounter, MAX(START) AS last_encounter,
       SUM(STOP IS NOT NULL AND STOP >= START) AS valid_durations,
       ROUND(SUM(TOTAL_CLAIM_COST), 2) AS total_claim_cost,
       ROUND(SUM(PAYER_COVERAGE), 2) AS covered_amount,
       ROUND(100.0 * SUM(PAYER_COVERAGE) / NULLIF(SUM(TOTAL_CLAIM_COST), 0), 2) AS weighted_coverage_pct
FROM encounters;

-- 5. Annual volumes; 2022 is an incomplete observation window, not a full year.
SELECT YEAR(START) AS year, COUNT(*) AS encounter_count,
       COUNT(DISTINCT PATIENT) AS active_patients,
       ROUND(SUM(TOTAL_CLAIM_COST), 2) AS total_claim_cost,
       MIN(START) AS first_start, MAX(START) AS last_start
FROM encounters GROUP BY YEAR(START) ORDER BY year;

-- 6. Duration sensitivity, not a clinical cleaning rule.
-- The >24h threshold is only a diagnostic for ambulatory/outpatient records.
WITH base AS (
    SELECT e.Id, e.ENCOUNTERCLASS, TIMESTAMPDIFF(SECOND,e.START,e.STOP)/3600.0 AS hours,
           (DATE(e.START) < p.BIRTHDATE OR (p.DEATHDATE IS NOT NULL AND
            (DATE(e.START)>p.DEATHDATE OR DATE(e.STOP)>p.DEATHDATE))) AS lifetime_flag
    FROM encounters e JOIN patients p ON p.Id=e.PATIENT
    WHERE e.ENCOUNTERCLASS IN ('ambulatory','outpatient')
      AND e.STOP IS NOT NULL AND e.STOP>=e.START
), scenarios AS (
    SELECT *, 'all_recorded' AS scenario FROM base
    UNION ALL SELECT *, 'without_over_24h' FROM base WHERE hours<=24
    UNION ALL SELECT *, 'without_lifetime_flags' FROM base WHERE NOT lifetime_flag
), ranked AS (
    SELECT *, ROW_NUMBER() OVER(PARTITION BY ENCOUNTERCLASS,scenario ORDER BY hours,Id) AS rn,
           COUNT(*) OVER(PARTITION BY ENCOUNTERCLASS,scenario) AS n
    FROM scenarios
)
SELECT ENCOUNTERCLASS AS encounter_class, scenario, COUNT(*) AS encounter_count,
       ROUND(AVG(hours),2) AS average_hours,
       ROUND(AVG(CASE WHEN rn IN(FLOOR((n+1)/2),FLOOR((n+2)/2)) THEN hours END),2) AS median_hours
FROM ranked GROUP BY ENCOUNTERCLASS,scenario ORDER BY ENCOUNTERCLASS,scenario;

-- 7. Financial sensitivity to lifetime flags, without altering source records.
WITH base AS (
    SELECT e.*,
           (DATE(e.START)<p.BIRTHDATE OR (p.DEATHDATE IS NOT NULL AND
            (DATE(e.START)>p.DEATHDATE OR DATE(e.STOP)>p.DEATHDATE))) AS lifetime_flag
    FROM encounters e JOIN patients p ON p.Id=e.PATIENT
), scenarios AS (
    SELECT *, 'all_recorded' AS scenario FROM base
    UNION ALL SELECT *, 'without_lifetime_flags' FROM base WHERE NOT lifetime_flag
)
SELECT scenario, COUNT(*) AS encounter_count,
       ROUND(SUM(TOTAL_CLAIM_COST),2) AS total_claim_cost,
       ROUND(SUM(PAYER_COVERAGE),2) AS covered_amount,
       ROUND(100.0*SUM(PAYER_COVERAGE)/NULLIF(SUM(TOTAL_CLAIM_COST),0),2) AS weighted_coverage_pct
FROM scenarios GROUP BY scenario ORDER BY scenario;
