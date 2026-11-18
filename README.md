# Debt Collection Data Analysis

A SQL Server project looking at collections performance and conduct risk in a debt collection business. I cleaned four messy tables, then answered 7 business questions covering how much is being collected, how customers are contacted, how vulnerable customers are treated, and where the compliance risks are.

I work in call quality and compliance, so I wanted a project where I could use what I know about FCA CONC and Consumer Duty alongside SQL.

The data is synthetic (no real customer data). It was set up like a typical messy export, with dates in different formats, inconsistent capitalisation, blanks and duplicate rows.

## Files

All four tables link on `account_id`.

- **accounts_raw.csv**: one row per debt account, with customer details, creditor, debt type, balances, status, vulnerability flag, DSAR/marketing consent and the agent assigned. Includes 15 duplicate rows.
- **payments_raw.csv**: payment history per account (date, amount, method, status).
- **communications_raw.csv**: contact log per account (calls, SMS, email, letters), including the call outcome and whether a CONC-compliant script was used.
- **compliance_flags_raw.csv**: compliance/QA flags raised on about 18% of accounts, e.g. missed DSAR deadlines, vulnerable customers not escalated, Consumer Duty risks, with severity and resolution status.

## Data cleaning

Each table was cleaned in SQL Server into a new `_clean` table. The raw tables were never changed, so every script can be rerun from scratch. Scripts are in `sql/`, numbered in run order, and each one ends with checks to confirm the results.

**Accounts** (`01_clean_accounts.sql`)

- Removed 15 duplicate rows
- Dates came in four different formats and were converted to a single date type
- Fixed customer name casing, including multi-word names
- Standardised status values and filled blanks

**Communications** (`02_clean_communications.sql`)

- No duplicates found
- Fixed mixed dates and inconsistent channel casing (e.g. "outbound call" vs "Inbound Call")
- Kept the inbound/outbound detail but added a `channel_type` column so all calls can be grouped together
- Converted call duration to a number; blank durations on emails, SMS and letters left empty so they don't drag averages down
- Script flag standardised to Yes / No / Unknown
- Found call outcomes (e.g. "Left Voicemail") and script flags recorded against emails and letters. Kept these rows but flagged them as a data quality issue

**Payments** (`03_clean_payments.sql`)

- No duplicates found
- `amount` was stored as text, which broke calculations. Converted to a proper money value
- Payment methods came in several casings ("DEBIT CARD", "debit card", "Debit Card") and were standardised
- Payments recorded only as "Card" were kept separate as "Card (Unspecified)", as there was no way to tell whether they were debit or credit
- Cash payments were picked up by the "Unknown" catch-all during testing and added to the mapping

**Compliance flags** (`04_clean_compliance_flags.sql`)

- No duplicates found
- Fixed mixed dates and inconsistent severity casing
- Standardised resolution status, and changed QA review from Y/N to Yes/No to match the other tables
- Added a check for Critical and High flags that are still open and not yet reviewed by QA
- Resolution status was first mapped without three values (Escalated, Under Review, Closed - No Action), which sent 176 flags to Unknown. Found while checking Q7, fixed and re-run

**Assumptions**

- Some dates such as `05/06/2025` could be UK or US format. Where both parts were 12 or under, they were treated as UK (DD/MM/YYYY)
- Apart from exact duplicates, no rows were deleted. Questionable records were kept and flagged so the analysis can decide how to treat them

---

## Analysis

All the queries are in `sql/05_analysis.sql` and run on the clean tables. I set out to answer 7 questions, and I ordered them so each one follows on from the last. I started with how much money is coming in, then looked at why it might not be, then at how customers are being treated, and finished with the compliance risks.

| # | Question | SQL used |
|---|---|---|
| Q1 | Collection rate by debt type | CTE, LEFT JOIN |
| Q2 | Payment failure rate by method | CTE, CASE inside SUM |
| Q3 | Vulnerable vs non-vulnerable customers | CTE, JOIN, SUM() OVER |
| Q4 | Script compliance by creditor and region | CTE, JOIN, RANK() |
| Q5 | Monthly collections and running total | CTE, SUM() OVER, LAG() |
| Q6 | Latest contact on each account | CTE, ROW_NUMBER() |
| Q7 | Open serious flags still being contacted | JOIN on two conditions |

---

### Q1. How much of each debt type is being collected?

I started here because the first thing a collections team wants to know is how much money is coming in.

```sql
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
```

I added up the payments for each account in a CTE before joining to accounts. If I joined first, each balance would be repeated once for every payment and the total owed would be too high. I only counted cleared payments, and used a LEFT JOIN so accounts with no payments were still included.

**What I found:** £277.6k has been collected out of £8.69m owed across 1,200 accounts, which is 3.2%. Store Card was highest at 3.8% and Credit Card was lowest at 2.6%, even though it has one of the biggest balances (£1.02m). There's only 1.2 points between the best and worst, so it's low across the board rather than one debt type pulling it down.

Since it's low everywhere, I wanted to check whether people were trying to pay and the payments were failing.

---

### Q2. Which payment methods fail the most?

```sql
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
```

The CASE inside SUM counts only the failed payments, and the second one adds up how much money they were worth.

**What I found:** 142 out of 2,033 payments failed (7.0%), worth £22.8k. Card (Unspecified) had the highest failure rate at 9.6%, then Direct Debit at 9.1%. I didn't expect that, as Direct Debit is usually one of the more reliable methods. Cheque was lowest at 3.4%. Debit Card only failed 6.6% of the time but lost the most money (£6.3k) because it had far more payments (714).

£22.8k is small compared to £8.69m owed, so failed payments aren't really why collection is low. Most customers just aren't paying. That made me want to look at who these customers are, starting with vulnerable customers, as they're the group Consumer Duty is most concerned with.

---

### Q3. Are vulnerable customers treated any differently?

Under Consumer Duty, vulnerable customers should get outcomes at least as good as everyone else. The vulnerability column has the type of vulnerability or "None", so I used a CTE to group them into vulnerable and not vulnerable first.

```sql
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
```

```sql
-- Q3b: outcome mix, vulnerable vs not
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
```

<details>
<summary>Q3c: customer said they were vulnerable but account not flagged</summary>

```sql
-- Q3c: vulnerability confirmed on a call but account not flagged
SELECT c.account_id, c.comm_date, c.agent, a.vulnerability_flag
FROM communications_clean c
JOIN accounts_clean a ON c.account_id = a.account_id
WHERE c.outcome = 'Customer Confirmed Vulnerability'
  AND a.vulnerability_flag = 'None'
ORDER BY c.comm_date;

-- totals
SELECT COUNT(*)                     AS contacts,
       COUNT(DISTINCT c.account_id) AS accounts,
       MIN(c.comm_date)             AS earliest,
       MAX(c.comm_date)             AS latest
FROM communications_clean c
JOIN accounts_clean a ON c.account_id = a.account_id
WHERE c.outcome = 'Customer Confirmed Vulnerability'
  AND a.vulnerability_flag = 'None';
```
</details>

In Q3b I used SUM(COUNT(*)) OVER (PARTITION BY ...) to show each outcome as a percentage of its own group. There are 1,084 non-vulnerable customers and only 116 vulnerable, so comparing counts wouldn't have been fair.

**What I found:**
- Vulnerable customers got slightly fewer compliant calls, 81.6% (160 of 196) compared with 85.5% (1,289 of 1,508). It's a small group so I wouldn't read too much into it, but it's going the wrong way.
- The outcomes were almost the same for both groups. Payment Arranged was 14.0% vs 13.7% and Complaint Raised 5.0% vs 4.4%. So vulnerable customers aren't getting worse outcomes, but I couldn't see any sign they were being handled differently either.
- The biggest issue was "Customer Confirmed Vulnerability" being recorded 101 times on accounts flagged as not vulnerable. That's 97 customers who told an agent they were vulnerable, but their account was never updated. If those were flagged properly, the vulnerable group would go from 116 to 213, nearly double.

From working in call quality, I know the script is how you show a customer has been treated fairly on a call. So after seeing a gap here, I wanted to see where compliance was weakest overall.

---

### Q4. Where is script compliance weakest?

I planned to rank individual agents, but when I checked there were 1,458 different agent names across 1,704 calls, so most agents only had one or two calls. Ranking them wouldn't have meant anything, so I ranked by creditor and region instead.

```sql
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
```

<details>
<summary>Q4b: same thing by region</summary>

```sql
-- Q4b: script compliance on calls, ranked by region
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
```
</details>

I kept "Unknown" as its own column so calls with no result recorded weren't counted as a pass or a fail.

**What I found:** 85.0% of calls used the compliant script overall. Vantage Home Finance was the lowest creditor at 82.2% and had the most non-compliant calls (19). Leeds City Council was highest at 87.2%. By region there was a wider spread, from Yorkshire at 80.4% to East Anglia at 88.3%. 154 calls were on accounts with no region, so they show as Unknown.

The thing that stood out was that more calls had no result recorded (145, 8.5%) than actually failed (110, 6.5%). Yorkshire was lowest mainly because it had the most unrecorded calls (22), not the most failures. If the result isn't recorded, the firm can't show the call was compliant, which is a risk on its own.

Q1 to Q4 are all snapshots, so next I wanted to see how things have changed over time.

---

### Q5. How are collections trending month by month?

```sql
-- Q5: monthly collections, running total and month-on-month change
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
```

The CTE gives one row per month, then SUM() OVER gives the running total and LAG() brings in the previous month so I could work out the change.

**What I found:** the data runs from October 2023 to September 2026. The running total finishes at £277,557.07, which matches the total from Q1, so the two queries agree. Monthly collections grew from a few hundred pounds at the start to around £10k a month in 2025, then levelled off. January to September 2026 brought in £100.3k, which is 8.9% more than the same months in 2025 (£92.1k). The best month was August 2026 at £14.2k.

The month-to-month changes jump around a lot (often 20 to 30% either way), so I wouldn't treat one bad month as a trend. The big early percentages like +524.9% are only because the starting amounts were so small.

There are no cleared payments in October 2026, and the only November 2026 payment is future-dated. Because LAG() looks at the previous row and not the previous month, November gets compared with September and shows -99.8%, which isn't a real drop. September (-40.1%) might also just be an incomplete month. In a real report I'd take out incomplete months first.

The trend shows the overall picture, but I also wanted to see where each account stands right now.

---

### Q6. What was the last contact on each account?

Before an agent calls a customer, they need to know when they were last contacted and what happened.

```sql
-- Q6: latest contact per account
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
```

<details>
<summary>Q6b and Q6c: last outcome summary and time since last contact</summary>

```sql
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
```
</details>

ROW_NUMBER() numbers each account's contacts with the newest as 1, so keeping rn = 1 gives one row per account. It has to go in a CTE because you can't filter on a window function in the WHERE clause. I added comm_id as a tie-breaker for contacts on the same day.

**What I found:** only 958 accounts have any contact on record, so 242 of the 1,200 accounts (20%) have never been contacted at all.

I grouped the last outcomes for the 958 contacted accounts:

| Where the account is | Last outcome | Accounts | % |
|---|---|---|---|
| Customer not reached | No Answer, Left Voicemail, Wrong Number, Call Dropped | 430 | 44.9% |
| Needs following up | Disputed Debt, Complaint Raised, Customer Confirmed Vulnerability, DSAR Request Logged | 171 | 17.8% |
| Payment arranged | Payment Arranged | 133 | 13.9% |
| Other | Requested Callback, Refused to Pay, Not Recorded | 224 | 23.4% |

Nearly half the accounts ended without the customer being reached, and only 13.9% ended with a payment arranged. This helps explain the 3.2% from Q1.

Most accounts have also gone quiet. 801 of the 958 (83.6%) haven't been contacted in over 90 days, and 337 (35.2%) in over a year. Including the 242 never contacted, that's 1,043 of the 1,200 accounts (86.9%) with no contact in the last 90 days.

Some of the oldest ones ended on things that should have been followed up. DC100214's last contact was a complaint 956 days ago, and DC100478 and DC100155 ended with a DSAR request about 910 days ago, with nothing after.

Once I knew the latest contact on each account, I could check it against the compliance flags.

---

### Q7. Are accounts with open serious flags still being contacted?

This is the question closest to my day job. If an account has an open Critical or High flag, for example a harassment complaint or a vulnerable customer who hasn't been escalated, contact should normally stop until it's sorted. Carrying on could cause the customer more harm.

```sql
-- Q7: open Critical/High flags with contact continuing after the flag was raised
-- open = anything not Resolved or Closed - No Action (Open, Escalated, Under Review)
SELECT f.account_id,
       f.flag_type,
       f.severity,
       f.resolution_status,
       f.date_raised,
       COUNT(c.comm_id)                               AS contacts_after_flag,
       MAX(c.comm_date)                               AS latest_contact,
       DATEDIFF(day, f.date_raised, MAX(c.comm_date)) AS days_flag_open_at_latest_contact
FROM compliance_flags_clean f
JOIN communications_clean c
     ON c.account_id = f.account_id
    AND c.comm_date > f.date_raised
WHERE f.severity IN ('Critical', 'High')
  AND f.resolution_status NOT IN ('Resolved', 'Closed - No Action')
GROUP BY f.account_id, f.flag_type, f.severity, f.resolution_status, f.date_raised
ORDER BY contacts_after_flag DESC;
```

The join has two conditions, the same account and a contact date after the flag was raised, so it only picks up contacts that happened after the flag.

**What I found:** 30 accounts with an open Critical or High flag were contacted again after the flag was raised, 66 contacts in total. 9 of these flags were Critical. Of the 30, 13 were Under Review, 9 had been Escalated and 8 were Open.

| Flag type | Accounts |
|---|---|
| Consumer Duty - Unfair Outcome Risk | 5 |
| Affordability Not Assessed | 5 |
| Incorrect Balance Quoted | 4 |
| Vulnerable Customer Not Escalated | 4 |
| Missed DSAR Deadline | 3 |
| Third Party Disclosure Risk | 3 |
| Harassment Complaint | 3 |
| Data Breach Risk | 2 |
| Recording Consent Missing | 1 |

The worst one was DC100388, a vulnerable customer who wasn't escalated and was contacted 9 more times over 335 days while the flag was still open, even though the flag itself had been escalated. 11 flags had been open for over a year by the latest contact, the longest being an incorrect balance quoted on DC100591 at 676 days.

A lot of these flags (harassment, vulnerability not escalated, affordability not assessed) are about how the customer is being contacted, so continuing to contact them could make things worse. In my current role I'd find these by sampling calls; here I could check every account at once.

**Note:** my first run of this query showed 41 accounts. While checking the results, I found the cleaning script had missed three resolution statuses (Escalated, Under Review, Closed - No Action), so 176 flags were marked as Unknown and "Closed - No Action" flags were being counted as open. I fixed the mapping in `04_clean_compliance_flags.sql` and re-ran Q7.

---

### Data issues I found during the analysis

- 5 contacts and 1 payment are dated after November 2026. I left them in as they make very little difference to the totals, but I'd want to know how they were recorded. One of them is DC100131's latest contact in Q7.
- Agent names were almost unique to each call (1,458 across 1,704 calls), so I couldn't measure individual agent performance.

---

## Summary

- **Collections:** only 3.2% of the £8.69m owed has been collected, and it's low for every debt type. Failed payments (£22.8k) are only a small part of the reason, though Direct Debit failing 9.1% of the time is worth looking into.
- **Contact:** this is the main reason collection is low. 20% of accounts have never been contacted, 86.9% have had no contact in 90 days, and nearly half of contacted accounts ended without reaching the customer.
- **Vulnerable customers:** they got slightly fewer compliant calls (81.6% vs 85.5%) and no sign of extra care. 97 customers said they were vulnerable but were never flagged.
- **Script compliance:** 85.0% overall, but more calls had no result recorded than actually failed. Vantage Home Finance and Yorkshire were lowest.
- **Trend:** collections grew to around £10k a month, and January to September 2026 is 8.9% up on the same period in 2025.
- **Risk:** 30 accounts with open Critical or High flags were contacted 66 more times after the flag was raised.

### What I'd recommend

1. Stop contact on accounts with open Critical or High flags until they've been reviewed, starting with the 30 from Q7.
2. Update the vulnerability flag whenever a customer confirms they're vulnerable on a call, and review the 97 accounts from Q3.
3. Make the script result a required field so every call's compliance can be shown, and focus QA checks on Yorkshire and Vantage Home Finance.
4. Make a plan to contact the 1,043 accounts with nothing in the last 90 days, starting with the 242 never contacted, and try different channels as so many calls aren't reaching people.
5. Look into why Direct Debits are failing.
6. Record agents with a proper ID so performance can be measured.

Next I'm building a Power BI dashboard from these results.

---

## Tools

SQL Server (SSMS), GitHub, and AI as a coding assistant. All queries were run and checked in SQL Server.

