# Debt Collection Dataset

This is a synthetic dataset built to practise SQL cleaning and Power BI analysis on something close to real debt collection data — no real customer data was used.

It's set up like a typical messy export: dates in different formats, inconsistent capitalisation, some blanks, and a handful of duplicate rows. Good for practising cleaning before you get to any analysis.

## Files

**accounts_raw.csv** — one row per debt account: customer details, creditor, debt type, balances, status, vulnerability flag, DSAR/marketing consent, and the agent assigned. Includes 15 duplicate rows.

**payments_raw.csv** — payment history per account (date, amount, method, status), linked by `account_id`.

**communications_raw.csv** — contact log per account (calls, SMS, email, letters), including call outcome and whether a CONC-compliant script was used.

**compliance_flags_raw.csv** — compliance/QA flags raised on about 18% of accounts, e.g. missed DSAR deadlines, vulnerable customers not escalated, Consumer Duty risks — with severity and resolution status.


All four link together on `account_id`.

## Ideas for analysis
Arrears aging, how vulnerable customers are handled, DSAR turnaround times, complaint trends by severity, script-compliance rate by agent.

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

**Assumptions**

- Some dates such as `05/06/2025` could be UK or US format. Where both parts were 12 or under, they were treated as UK (DD/MM/YYYY)
- Apart from exact duplicates, no rows were deleted. Questionable records were kept and flagged so the analysis can decide how to treat them

**Tools**

SQL Server (SSMS), GitHub, and AI as a coding assistant. All queries were run and validated in SQL Server.
