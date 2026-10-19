-- 04_clean_compliance_flags.sql
-- Cleans compliance_flags -> compliance_flags_clean
-- Author: Abdul | Oct 2026

IF OBJECT_ID('compliance_flags_clean', 'U') IS NOT NULL
    DROP TABLE compliance_flags_clean;

SELECT DISTINCT
    UPPER(TRIM(flag_id))    AS flag_id,
    UPPER(TRIM(account_id)) AS account_id,

    -- uk first for slash dates
    CASE
        WHEN TRIM(date_raised) LIKE '____-__-__' THEN TRY_CONVERT(date, TRIM(date_raised), 23)
        WHEN TRIM(date_raised) LIKE '__-__-____' THEN TRY_CONVERT(date, TRIM(date_raised), 105)
        WHEN TRIM(date_raised) LIKE '__/__/____' THEN COALESCE(
                 TRY_CONVERT(date, TRIM(date_raised), 103),
                 TRY_CONVERT(date, TRIM(date_raised), 101))
    END AS date_raised,

    -- casing already ok
    TRIM(flag_type) AS flag_type,

    CASE
        WHEN UPPER(TRIM(severity)) = 'CRITICAL' THEN 'Critical'
        WHEN UPPER(TRIM(severity)) = 'HIGH'     THEN 'High'
        WHEN UPPER(TRIM(severity)) = 'MEDIUM'   THEN 'Medium'
        WHEN UPPER(TRIM(severity)) = 'LOW'      THEN 'Low'
        ELSE 'Unknown'
    END AS severity,

    CASE
        WHEN UPPER(TRIM(resolution_status)) = 'OPEN'        THEN 'Open'
        WHEN UPPER(TRIM(resolution_status)) = 'IN PROGRESS' THEN 'In Progress'
        WHEN UPPER(TRIM(resolution_status)) = 'RESOLVED'    THEN 'Resolved'
        WHEN UPPER(TRIM(resolution_status)) = 'CLOSED'      THEN 'Closed'
        ELSE 'Unknown'
    END AS resolution_status,

    CASE
        WHEN UPPER(TRIM(reviewed_by_qa)) IN ('Y', 'YES') THEN 'Yes'
        WHEN UPPER(TRIM(reviewed_by_qa)) IN ('N', 'NO')  THEN 'No'
        ELSE 'Unknown'
    END AS reviewed_by_qa

INTO compliance_flags_clean
FROM compliance_flags;


------------------------------------------------------------
-- checks
------------------------------------------------------------

SELECT (SELECT COUNT(*) FROM compliance_flags)       AS raw_rows,
       (SELECT COUNT(*) FROM compliance_flags_clean) AS clean_rows;

-- bad dates
SELECT r.flag_id, r.date_raised
FROM compliance_flags r
JOIN compliance_flags_clean c ON UPPER(TRIM(r.flag_id)) = c.flag_id
WHERE c.date_raised IS NULL;

-- categories
SELECT flag_type, COUNT(*) AS n
FROM compliance_flags_clean
GROUP BY flag_type
ORDER BY flag_type;

SELECT r.severity AS raw_severity, c.severity, COUNT(*) AS n
FROM compliance_flags r
JOIN compliance_flags_clean c ON UPPER(TRIM(r.flag_id)) = c.flag_id
GROUP BY r.severity, c.severity
ORDER BY c.severity;

SELECT r.resolution_status AS raw_status, c.resolution_status, COUNT(*) AS n
FROM compliance_flags r
JOIN compliance_flags_clean c ON UPPER(TRIM(r.flag_id)) = c.flag_id
GROUP BY r.resolution_status, c.resolution_status
ORDER BY c.resolution_status;

SELECT r.reviewed_by_qa AS raw_qa, c.reviewed_by_qa, COUNT(*) AS n
FROM compliance_flags r
JOIN compliance_flags_clean c ON UPPER(TRIM(r.flag_id)) = c.flag_id
GROUP BY r.reviewed_by_qa, c.reviewed_by_qa;

-- dupes
SELECT flag_id, COUNT(*) AS copies
FROM compliance_flags_clean
GROUP BY flag_id
HAVING COUNT(*) > 1;

SELECT account_id, date_raised, flag_type, COUNT(*) AS copies
FROM compliance_flags_clean
GROUP BY account_id, date_raised, flag_type
HAVING COUNT(*) > 1;

-- orphans
SELECT f.account_id, COUNT(*) AS n
FROM compliance_flags_clean f
LEFT JOIN accounts_clean a ON f.account_id = a.account_id
WHERE a.account_id IS NULL
GROUP BY f.account_id;

-- future dated
SELECT COUNT(*) AS future_flags
FROM compliance_flags_clean
WHERE date_raised > CAST(GETDATE() AS date);

-- open high risk flags
SELECT severity, resolution_status, reviewed_by_qa, COUNT(*) AS n
FROM compliance_flags_clean
WHERE severity IN ('Critical', 'High')
  AND resolution_status NOT IN ('Resolved', 'Closed')
GROUP BY severity, resolution_status, reviewed_by_qa
ORDER BY severity, n DESC;
