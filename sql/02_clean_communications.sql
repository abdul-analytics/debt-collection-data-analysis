-- 02_clean_communications.sql
-- Cleans communications -> communications_clean
-- Author: Abdul | Oct 2026

IF OBJECT_ID('communications_clean', 'U') IS NOT NULL
    DROP TABLE communications_clean;

SELECT DISTINCT
    UPPER(TRIM(comm_id))    AS comm_id,
    UPPER(TRIM(account_id)) AS account_id,

    -- mixed date formats. slash dates tried as UK first, US if that fails
    -- note: ambiguous dates (day and month both <= 12) end up as UK
    CASE
        WHEN TRIM(comm_date) LIKE '____-__-__' THEN TRY_CONVERT(date, TRIM(comm_date), 23)
        WHEN TRIM(comm_date) LIKE '__-__-____' THEN TRY_CONVERT(date, TRIM(comm_date), 105)
        WHEN TRIM(comm_date) LIKE '__/__/____' THEN COALESCE(
                 TRY_CONVERT(date, TRIM(comm_date), 103),
                 TRY_CONVERT(date, TRIM(comm_date), 101))
    END AS comm_date,

    CASE
        WHEN UPPER(TRIM(channel)) = 'INBOUND CALL'  THEN 'Inbound Call'
        WHEN UPPER(TRIM(channel)) = 'OUTBOUND CALL' THEN 'Outbound Call'
        WHEN UPPER(TRIM(channel)) = 'CALL'          THEN 'Call'
        WHEN UPPER(TRIM(channel)) = 'SMS'           THEN 'SMS'
        WHEN UPPER(TRIM(channel)) = 'EMAIL'         THEN 'Email'
        WHEN UPPER(TRIM(channel)) = 'LETTER'        THEN 'Letter'
        ELSE 'Unknown'
    END AS channel,

    -- grouped version so all calls can be analysed together
    CASE
        WHEN UPPER(TRIM(channel)) LIKE '%CALL%' THEN 'Call'
        WHEN UPPER(TRIM(channel)) = 'SMS'       THEN 'SMS'
        WHEN UPPER(TRIM(channel)) = 'EMAIL'     THEN 'Email'
        WHEN UPPER(TRIM(channel)) = 'LETTER'    THEN 'Letter'
        ELSE 'Unknown'
    END AS channel_type,

    -- blank for non-calls, kept as NULL so averages aren't skewed
    TRY_CONVERT(decimal(6,1), NULLIF(TRIM(CAST(duration_minutes AS varchar(20))), '')) AS duration_minutes,

    ISNULL(NULLIF(TRIM(outcome), ''), 'Not Recorded') AS outcome,

    CASE
        WHEN UPPER(TRIM(conc_compliant_script_used)) IN ('Y', 'YES') THEN 'Yes'
        WHEN UPPER(TRIM(conc_compliant_script_used)) IN ('N', 'NO')  THEN 'No'
        ELSE 'Unknown'
    END AS conc_compliant_script_used,

    ISNULL(NULLIF(TRIM(agent), ''), 'Unassigned') AS agent

INTO communications_clean
FROM communications;


------------------------------------------------------------
-- checks
------------------------------------------------------------

-- row counts before/after
SELECT (SELECT COUNT(*) FROM communications)       AS raw_rows,
       (SELECT COUNT(*) FROM communications_clean) AS clean_rows;

-- dates that didn't convert
SELECT r.comm_id, r.comm_date AS raw_date
FROM communications r
JOIN communications_clean c ON UPPER(TRIM(r.comm_id)) = c.comm_id
WHERE c.comm_date IS NULL;

-- category values
SELECT channel, channel_type, COUNT(*) AS n FROM communications_clean GROUP BY channel, channel_type;
SELECT outcome, COUNT(*) AS n FROM communications_clean GROUP BY outcome ORDER BY outcome;
SELECT conc_compliant_script_used, COUNT(*) AS n FROM communications_clean GROUP BY conc_compliant_script_used;

-- duplicate comm_ids
SELECT comm_id, COUNT(*) AS copies
FROM communications_clean
GROUP BY comm_id
HAVING COUNT(*) > 1;

-- duration by channel type
SELECT channel_type,
       SUM(CASE WHEN duration_minutes IS NULL THEN 1 ELSE 0 END) AS no_duration,
       SUM(CASE WHEN duration_minutes <= 0 THEN 1 ELSE 0 END)    AS zero_or_negative,
       SUM(CASE WHEN duration_minutes > 60 THEN 1 ELSE 0 END)    AS over_60_mins,
       MIN(duration_minutes) AS min_mins,
       MAX(duration_minutes) AS max_mins
FROM communications_clean
GROUP BY channel_type;

-- contacts with no matching account
SELECT c.account_id, COUNT(*) AS n
FROM communications_clean c
LEFT JOIN accounts_clean a ON c.account_id = a.account_id
WHERE a.account_id IS NULL
GROUP BY c.account_id;

-- future dated contacts
SELECT COUNT(*) AS future_contacts
FROM communications_clean
WHERE comm_date > CAST(GETDATE() AS date);

-- call outcomes logged against non-call channels
SELECT channel_type, outcome, COUNT(*) AS n
FROM communications_clean
WHERE channel_type <> 'Call'
  AND outcome IN ('Left Voicemail', 'Call Dropped')
GROUP BY channel_type, outcome;

-- script flag on non-call channels (should only apply to calls)
SELECT channel_type, conc_compliant_script_used, COUNT(*) AS n
FROM communications_clean
WHERE channel_type <> 'Call'
GROUP BY channel_type, conc_compliant_script_used;
