-- ============================================================
-- Accounts table — exploratory / step-by-step cleaning tests
-- Each block below was tested individually before being combined
-- into the final cleaning script (see sql/01_clean_accounts.sql)
-- ============================================================

-- Step 1: Check for duplicate account_id values
SELECT account_id, COUNT(*)
FROM [dbo].[accounts]
GROUP BY account_id
HAVING COUNT(*) > 1;
-- Found ~15 duplicated account_ids, matching the known duplicate rows


-- Step 2: Fixing name capitalisation
-- Initial attempt (UPPER first letter of whole string) only fixed the
-- first word and left surnames lowercase, e.g. "Donald Mills" -> "Donald mills"
-- Fixed version below splits on spaces and capitalises each word separately
SELECT customer_name,
    (
        SELECT STRING_AGG(
            UPPER(LEFT(value,1)) + LOWER(SUBSTRING(value,2,LEN(value))), ' '
        )
        FROM STRING_SPLIT(LTRIM(RTRIM(customer_name)), ' ')
    ) AS cleaned_name
FROM accounts;


-- Step 3: Standardising date format (date_of_birth)
-- Dates appear in three formats: YYYY-MM-DD, DD-MM-YYYY, and __/__/____
-- The __/__/____ format is itself mixed between DD/MM/YYYY and MM/DD/YYYY
-- (e.g. "10/28/1964" can only be MM/DD/YYYY since there's no 28th month)
-- so DD/MM/YYYY is tried first, falling back to MM/DD/YYYY if that fails
SELECT date_of_birth,
    CASE
        WHEN date_of_birth LIKE '____-__-__' THEN TRY_CONVERT(date, date_of_birth, 23)
        WHEN date_of_birth LIKE '__-__-____' THEN TRY_CONVERT(date, date_of_birth, 105)
        WHEN date_of_birth LIKE '__/__/____'
             AND TRY_CONVERT(date, date_of_birth, 103) IS NOT NULL
             THEN TRY_CONVERT(date, date_of_birth, 103)  -- DD/MM/YYYY works
        WHEN date_of_birth LIKE '__/__/____'
             THEN TRY_CONVERT(date, date_of_birth, 101)  -- fallback to MM/DD/YYYY
        ELSE NULL
    END AS cleaned_dob
FROM accounts;


-- Step 4: Standardising status casing and filling blanks
-- account_status has inconsistent casing (Open / OPEN / open)
-- vulnerability_flag and marketing_consent have blank values that
-- should be treated as "None" / "Unknown" rather than left empty
SELECT account_status,
    UPPER(LEFT(LTRIM(RTRIM(account_status)),1)) + LOWER(SUBSTRING(LTRIM(RTRIM(account_status)),2,LEN(account_status))) AS cleaned_status,
    vulnerability_flag,
    ISNULL(NULLIF(LTRIM(RTRIM(vulnerability_flag)), ''), 'None') AS cleaned_vuln,
    marketing_consent,
    ISNULL(NULLIF(LTRIM(RTRIM(marketing_consent)), ''), 'Unknown') AS cleaned_consent
FROM accounts;
