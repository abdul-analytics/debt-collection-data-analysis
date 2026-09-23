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
