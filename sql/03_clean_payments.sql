-- 03_clean_payments.sql
-- Cleans payments -> payments_clean
-- Author: Abdul | Oct 2026

IF OBJECT_ID('payments_clean', 'U') IS NOT NULL
    DROP TABLE payments_clean;

SELECT DISTINCT
    UPPER(TRIM(payment_id)) AS payment_id,
    UPPER(TRIM(account_id)) AS account_id,

    -- same date logic as accounts/comms (UK first for slash dates)
    CASE
        WHEN TRIM(payment_date) LIKE '____-__-__' THEN TRY_CONVERT(date, TRIM(payment_date), 23)
        WHEN TRIM(payment_date) LIKE '__-__-____' THEN TRY_CONVERT(date, TRIM(payment_date), 105)
        WHEN TRIM(payment_date) LIKE '__/__/____' THEN COALESCE(
                 TRY_CONVERT(date, TRIM(payment_date), 103),
                 TRY_CONVERT(date, TRIM(payment_date), 101))
    END AS payment_date,

    -- amount came in as varchar
    TRY_CONVERT(decimal(10,2),
        REPLACE(REPLACE(NULLIF(TRIM(amount), ''), N'£', ''), ',', '')) AS amount,

    CASE
        WHEN UPPER(TRIM(payment_method)) = 'DEBIT CARD'     THEN 'Debit Card'
        WHEN UPPER(TRIM(payment_method)) = 'CARD'           THEN 'Card (Unspecified)'  -- could be debit or credit
        WHEN UPPER(TRIM(payment_method)) = 'BANK TRANSFER'  THEN 'Bank Transfer'
        WHEN UPPER(TRIM(payment_method)) = 'DIRECT DEBIT'   THEN 'Direct Debit'
        WHEN UPPER(TRIM(payment_method)) = 'STANDING ORDER' THEN 'Standing Order'
        WHEN UPPER(TRIM(payment_method)) = 'CHEQUE'         THEN 'Cheque'
        WHEN UPPER(TRIM(payment_method)) = 'CASH'           THEN 'Cash'
        ELSE 'Unknown'
    END AS payment_method,

    CASE
        WHEN UPPER(TRIM(payment_status)) = 'CLEARED' THEN 'Cleared'
        WHEN UPPER(TRIM(payment_status)) = 'FAILED'  THEN 'Failed'
        WHEN UPPER(TRIM(payment_status)) = 'PENDING' THEN 'Pending'
        ELSE 'Unknown'
    END AS payment_status

INTO payments_clean
FROM payments;


------------------------------------------------------------
-- checks
------------------------------------------------------------

SELECT (SELECT COUNT(*) FROM payments)       AS raw_rows,
       (SELECT COUNT(*) FROM payments_clean) AS clean_rows;

-- dates not converted
SELECT r.payment_id, r.payment_date
FROM payments r
JOIN payments_clean c ON UPPER(TRIM(r.payment_id)) = c.payment_id
WHERE c.payment_date IS NULL;

-- amounts not converted
SELECT r.payment_id, r.amount
FROM payments r
JOIN payments_clean c ON UPPER(TRIM(r.payment_id)) = c.payment_id
WHERE c.amount IS NULL;

-- method / status mapping
SELECT r.payment_method AS raw_method, c.payment_method, COUNT(*) AS n
FROM payments r
JOIN payments_clean c ON UPPER(TRIM(r.payment_id)) = c.payment_id
GROUP BY r.payment_method, c.payment_method
ORDER BY c.payment_method;

SELECT r.payment_status AS raw_status, c.payment_status, COUNT(*) AS n
FROM payments r
JOIN payments_clean c ON UPPER(TRIM(r.payment_id)) = c.payment_id
GROUP BY r.payment_status, c.payment_status
ORDER BY c.payment_status;

-- dupes
SELECT payment_id, COUNT(*) AS copies
FROM payments_clean
GROUP BY payment_id
HAVING COUNT(*) > 1;

SELECT account_id, payment_date, amount, payment_method, COUNT(*) AS copies
FROM payments_clean
GROUP BY account_id, payment_date, amount, payment_method
HAVING COUNT(*) > 1;

-- amount range
SELECT MIN(amount) AS min_amt,
       MAX(amount) AS max_amt,
       AVG(amount) AS avg_amt,
       SUM(CASE WHEN amount <= 0 THEN 1 ELSE 0 END) AS zero_or_negative
FROM payments_clean;

SELECT TOP 10 payment_id, account_id, payment_date, amount, payment_method
FROM payments_clean
ORDER BY amount DESC;

-- no matching account
SELECT p.account_id, COUNT(*) AS n
FROM payments_clean p
LEFT JOIN accounts_clean a ON p.account_id = a.account_id
WHERE a.account_id IS NULL
GROUP BY p.account_id;

-- future dated
SELECT COUNT(*) AS future_payments
FROM payments_clean
WHERE payment_date > CAST(GETDATE() AS date);

-- totals by status (failed shouldn't count as collected)
SELECT payment_status, COUNT(*) AS n, SUM(amount) AS total_amount
FROM payments_clean
GROUP BY payment_status;
