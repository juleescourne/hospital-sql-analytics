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
       d.average_hours, d.median_hours
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
FROM procedures pr JOIN encounters e ON e.Id = pr.ENCOUNTER WHERE pr.PATIENT <> e.PATIENT;

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
