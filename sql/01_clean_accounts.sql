-- ============================================================
-- Clean the accounts table
-- Source: accounts (raw import of accounts_raw.csv)
-- Output: accounts_clean (new permanent table)
--
-- Fixes applied:
--   - Removes 15 duplicate rows (SELECT DISTINCT)
--   - Capitalises each word of customer_name correctly
--   - Parses date_of_birth and default_date from mixed formats
--     (YYYY-MM-DD, DD-MM-YYYY, DD/MM/YYYY, and MM/DD/YYYY)
--   - Standardises postcode/region casing and blanks
--   - Converts balance/interest columns to proper decimal types
--   - Standardises account_status casing
--   - Fills blank vulnerability_flag with 'None'
--   - Fills blank marketing_consent with 'Unknown'
-- ============================================================

IF OBJECT_ID('accounts_clean', 'U') IS NOT NULL
    DROP TABLE accounts_clean;

SELECT DISTINCT
    account_id,

    (
        SELECT STRING_AGG(
            UPPER(LEFT(value,1)) + LOWER(SUBSTRING(value,2,LEN(value))), ' '
        )
        FROM STRING_SPLIT(LTRIM(RTRIM(customer_name)), ' ')
    ) AS customer_name,

    CASE
        WHEN date_of_birth LIKE '____-__-__' THEN TRY_CONVERT(date, date_of_birth, 23)
        WHEN date_of_birth LIKE '__-__-____' THEN TRY_CONVERT(date, date_of_birth, 105)
        WHEN date_of_birth LIKE '__/__/____'
             AND TRY_CONVERT(date, date_of_birth, 103) IS NOT NULL
             THEN TRY_CONVERT(date, date_of_birth, 103)
        WHEN date_of_birth LIKE '__/__/____'
             THEN TRY_CONVERT(date, date_of_birth, 101)
        ELSE NULL
    END AS date_of_birth,

    NULLIF(LTRIM(RTRIM(UPPER(postcode))), '') AS postcode,
    NULLIF(LTRIM(RTRIM(region)), '') AS region,
    creditor,
    debt_type,
    TRY_CONVERT(decimal(10,2), NULLIF(original_balance, '')) AS original_balance,
    TRY_CONVERT(decimal(10,2), NULLIF(current_balance, '')) AS current_balance,
    TRY_CONVERT(decimal(5,2), NULLIF(interest_rate_pct, '')) AS interest_rate_pct,

    CASE
        WHEN default_date LIKE '____-__-__' THEN TRY_CONVERT(date, default_date, 23)
        WHEN default_date LIKE '__-__-____' THEN TRY_CONVERT(date, default_date, 105)
        WHEN default_date LIKE '__/__/____'
             AND TRY_CONVERT(date, default_date, 103) IS NOT NULL
             THEN TRY_CONVERT(date, default_date, 103)
        WHEN default_date LIKE '__/__/____'
             THEN TRY_CONVERT(date, default_date, 101)
        ELSE NULL
    END AS default_date,

    UPPER(LEFT(LTRIM(RTRIM(account_status)),1)) + LOWER(SUBSTRING(LTRIM(RTRIM(account_status)),2,LEN(account_status))) AS account_status,
    ISNULL(NULLIF(LTRIM(RTRIM(vulnerability_flag)), ''), 'None') AS vulnerability_flag,
    dsar_requested,
    ISNULL(NULLIF(LTRIM(RTRIM(marketing_consent)), ''), 'Unknown') AS marketing_consent,
    assigned_agent

INTO accounts_clean
FROM accounts;

-- Verification
SELECT COUNT(*) AS raw_row_count FROM accounts;
SELECT COUNT(*) AS clean_row_count FROM accounts_clean;
SELECT * FROM accounts_clean;
