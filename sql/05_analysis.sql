-- 05_analysis.sql
-- Analysis questions Q1 to Q7, run on the clean tables
-- Author: Abdul | Nov 2026


-- Q1: collection rate by debt type
-- payments totalled per account first to avoid double counting balances
WITH paid AS (
    SELECT account_id, SUM(amount) AS total_paid
    FROM payments_clean
    WHERE payment_status = 'Cleared'
    GROUP BY account_id
)
SELECT a.debt_type,
       COUNT(*)                                  AS accounts,
       SUM(a.original_balance)                   AS total_owed,
       SUM(ISNULL(p.total_paid, 0))              AS total_collected,
       ROUND(100.0 * SUM(ISNULL(p.total_paid, 0))
             / NULLIF(SUM(a.original_balance), 0), 1) AS collection_rate_pct
FROM accounts_clean a
LEFT JOIN paid p ON a.account_id = p.account_id
GROUP BY a.debt_type
ORDER BY collection_rate_pct DESC;


-- Q2: payment failure rate by method
WITH method_stats AS (
    SELECT payment_method,
           COUNT(*) AS total_payments,
           SUM(CASE WHEN payment_status = 'Failed' THEN 1 ELSE 0 END)      AS failed_payments,
           SUM(CASE WHEN payment_status = 'Failed' THEN amount ELSE 0 END) AS failed_amount
    FROM payments_clean
    GROUP BY payment_method
)
SELECT payment_method,
       total_payments,
       failed_payments,
       failed_amount,
       ROUND(100.0 * failed_payments / total_payments, 1) AS failure_rate_pct
FROM method_stats
ORDER BY failure_rate_pct DESC;


-- Q3a: script compliance on calls, vulnerable vs not
WITH accts AS (
    SELECT account_id,
           vulnerability_flag AS vulnerability_type,
           CASE WHEN vulnerability_flag = 'None' THEN 'Not vulnerable'
                ELSE 'Vulnerable' END AS vulnerable
    FROM accounts_clean
)
SELECT a.vulnerable,
       COUNT(*) AS calls,
       SUM(CASE WHEN c.conc_compliant_script_used = 'Yes' THEN 1 ELSE 0 END) AS compliant_calls,
       ROUND(100.0 * SUM(CASE WHEN c.conc_compliant_script_used = 'Yes' THEN 1 ELSE 0 END)
             / COUNT(*), 1) AS compliance_rate_pct
FROM communications_clean c
JOIN accts a ON c.account_id = a.account_id
WHERE c.channel_type = 'Call'
GROUP BY a.vulnerable;


-- Q3b: outcome mix, vulnerable vs not
-- % of each group, as group sizes are very different (1,084 vs 116)
WITH accts AS (
    SELECT account_id,
           CASE WHEN vulnerability_flag = 'None' THEN 'Not vulnerable'
                ELSE 'Vulnerable' END AS vulnerable
    FROM accounts_clean
)
SELECT a.vulnerable,
       c.outcome,
       COUNT(*) AS n,
       ROUND(100.0 * COUNT(*)
             / SUM(COUNT(*)) OVER (PARTITION BY a.vulnerable), 1) AS pct_of_group
FROM communications_clean c
JOIN accts a ON c.account_id = a.account_id
GROUP BY a.vulnerable, c.outcome
ORDER BY a.vulnerable, n DESC;


-- Q3c: vulnerability confirmed on a call but account not flagged
SELECT c.account_id, c.comm_date, c.agent, a.vulnerability_flag
FROM communications_clean c
JOIN accounts_clean a ON c.account_id = a.account_id
WHERE c.outcome = 'Customer Confirmed Vulnerability'
  AND a.vulnerability_flag = 'None'
ORDER BY c.comm_date;

-- Q3c totals
SELECT COUNT(*)                     AS contacts,
       COUNT(DISTINCT c.account_id) AS accounts,
       MIN(c.comm_date)             AS earliest,
       MAX(c.comm_date)             AS latest
FROM communications_clean c
JOIN accounts_clean a ON c.account_id = a.account_id
WHERE c.outcome = 'Customer Confirmed Vulnerability'
  AND a.vulnerability_flag = 'None';


-- Q4: script compliance on calls, ranked by creditor
-- agent level not used: 1,458 agents across 1,704 calls, too few calls each to rank fairly
WITH creditor_stats AS (
    SELECT a.creditor,
           COUNT(*) AS calls,
           SUM(CASE WHEN c.conc_compliant_script_used = 'Yes'     THEN 1 ELSE 0 END) AS compliant,
           SUM(CASE WHEN c.conc_compliant_script_used = 'No'      THEN 1 ELSE 0 END) AS non_compliant,
           SUM(CASE WHEN c.conc_compliant_script_used = 'Unknown' THEN 1 ELSE 0 END) AS not_recorded
    FROM communications_clean c
    JOIN accounts_clean a ON c.account_id = a.account_id
    WHERE c.channel_type = 'Call'
    GROUP BY a.creditor
)
SELECT creditor,
       calls,
       compliant,
       non_compliant,
       not_recorded,
       ROUND(100.0 * compliant / calls, 1) AS compliance_rate_pct,
       RANK() OVER (ORDER BY 1.0 * compliant / calls ASC) AS worst_rank
FROM creditor_stats
ORDER BY worst_rank;


-- Q4b: script compliance on calls, ranked by region
-- blank regions grouped as Unknown
WITH region_stats AS (
    SELECT ISNULL(a.region, 'Unknown') AS region,
           COUNT(*) AS calls,
           SUM(CASE WHEN c.conc_compliant_script_used = 'Yes'     THEN 1 ELSE 0 END) AS compliant,
           SUM(CASE WHEN c.conc_compliant_script_used = 'No'      THEN 1 ELSE 0 END) AS non_compliant,
           SUM(CASE WHEN c.conc_compliant_script_used = 'Unknown' THEN 1 ELSE 0 END) AS not_recorded
    FROM communications_clean c
    JOIN accounts_clean a ON c.account_id = a.account_id
    WHERE c.channel_type = 'Call'
    GROUP BY ISNULL(a.region, 'Unknown')
)
SELECT region,
       calls,
       compliant,
       non_compliant,
       not_recorded,
       ROUND(100.0 * compliant / calls, 1) AS compliance_rate_pct,
       RANK() OVER (ORDER BY 1.0 * compliant / calls ASC) AS worst_rank
FROM region_stats
ORDER BY worst_rank;


-- Q5: monthly collections, running total and month-on-month change
-- note: lag compares with the previous row, so a missing month (oct 2026) skews the next one
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(payment_date), MONTH(payment_date), 1) AS month_start,
           COUNT(*)    AS payments,
           SUM(amount) AS collected
    FROM payments_clean
    WHERE payment_status = 'Cleared'
      AND payment_date IS NOT NULL
    GROUP BY DATEFROMPARTS(YEAR(payment_date), MONTH(payment_date), 1)
)
SELECT month_start,
       payments,
       collected,
       SUM(collected) OVER (ORDER BY month_start) AS running_total,
       LAG(collected) OVER (ORDER BY month_start) AS prev_month,
       collected - LAG(collected) OVER (ORDER BY month_start) AS change,
       ROUND(100.0 * (collected - LAG(collected) OVER (ORDER BY month_start))
             / NULLIF(LAG(collected) OVER (ORDER BY month_start), 0), 1) AS pct_change
FROM monthly
ORDER BY month_start;


-- Q6: latest contact per account
-- comm_id breaks ties on the same day
WITH ranked AS (
    SELECT account_id,
           comm_date,
           channel,
           outcome,
           ROW_NUMBER() OVER (PARTITION BY account_id
                              ORDER BY comm_date DESC, comm_id DESC) AS rn
    FROM communications_clean
    WHERE comm_date IS NOT NULL
)
SELECT account_id,
       comm_date AS last_contact_date,
       channel   AS last_channel,
       outcome   AS last_outcome,
       DATEDIFF(day, comm_date, CAST(GETDATE() AS date)) AS days_since_contact
FROM ranked
WHERE rn = 1
ORDER BY days_since_contact DESC;


-- Q6b: what state are accounts in, based on their latest contact
WITH ranked AS (
    SELECT account_id, outcome,
           ROW_NUMBER() OVER (PARTITION BY account_id
                              ORDER BY comm_date DESC, comm_id DESC) AS rn
    FROM communications_clean
    WHERE comm_date IS NOT NULL
)
SELECT outcome AS last_outcome,
       COUNT(*) AS accounts,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_accounts
FROM ranked
WHERE rn = 1
GROUP BY outcome
ORDER BY accounts DESC;


-- Q6c: how long since each account was last contacted
WITH ranked AS (
    SELECT account_id, comm_date,
           ROW_NUMBER() OVER (PARTITION BY account_id
                              ORDER BY comm_date DESC, comm_id DESC) AS rn
    FROM communications_clean
    WHERE comm_date IS NOT NULL
)
SELECT COUNT(*) AS accounts,
       SUM(CASE WHEN DATEDIFF(day, comm_date, CAST(GETDATE() AS date)) > 90  THEN 1 ELSE 0 END) AS over_90_days,
       SUM(CASE WHEN DATEDIFF(day, comm_date, CAST(GETDATE() AS date)) > 180 THEN 1 ELSE 0 END) AS over_180_days,
       SUM(CASE WHEN DATEDIFF(day, comm_date, CAST(GETDATE() AS date)) > 365 THEN 1 ELSE 0 END) AS over_1_year
FROM ranked
WHERE rn = 1;


-- Q7: open Critical/High flags with contact continuing after the flag was raised
-- join on two conditions: same account and contact after the flag date
SELECT f.account_id,
       f.flag_type,
       f.severity,
       f.date_raised,
       COUNT(c.comm_id)                               AS contacts_after_flag,
       MAX(c.comm_date)                               AS latest_contact,
       DATEDIFF(day, f.date_raised, MAX(c.comm_date)) AS days_flag_open_at_latest_contact
FROM compliance_flags_clean f
JOIN communications_clean c
     ON c.account_id = f.account_id
    AND c.comm_date > f.date_raised
WHERE f.severity IN ('Critical', 'High')
  AND f.resolution_status NOT IN ('Resolved', 'Closed')
GROUP BY f.account_id, f.flag_type, f.severity, f.date_raised
ORDER BY contacts_after_flag DESC;


-- data checks: future-dated records
SELECT COUNT(*) AS future_contacts
FROM communications_clean
WHERE comm_date > CAST(GETDATE() AS date);

SELECT COUNT(*) AS future_payments
FROM payments_clean
WHERE payment_date > CAST(GETDATE() AS date);
