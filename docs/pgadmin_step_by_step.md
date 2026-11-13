# Running the project in pgAdmin 4 (macOS)

You need PostgreSQL and pgAdmin 4 installed, and to know your `postgres` user password.

## 1. Get the project onto your Mac
Download or clone the repo, e.g. into `~/sql/retail-revenue-sql-analysis`.

## 2. Create the database (step 00)
1. Open **pgAdmin 4** → expand **Servers** → your server (enter the password).
2. Right-click **Databases** → **Create** → **Database…**
3. Name: `retail_analytics` → **Save**.

   *(Or: select the `postgres` database → **Tools → Query Tool** → open `sql/00_create_database.sql` → F5.)*

## 3. Open a Query Tool on the new database
Click **retail_analytics** in the tree → **Tools → Query Tool** (or press ⌥⇧Q).

## 4. Run scripts 01 → 13 in order
For each file:
1. In the Query Tool, click the **Open File** icon → choose the script from `sql/`.
2. Press **F5** (or ▶ Execute).
3. Check the **Messages** tab says *Query returned successfully*.

| Order | File | What you should see |
|------:|------|--------------------|
| 1 | `01_create_staging_tables.sql` | schema `staging` with 4 tables |
| 2 | `02_load_data.sql` | `COMMIT` |
| 3 | `03_data_quality_checks.sql` | data-quality result sets (see tip below) |
| 4 | `04_clean_transform.sql` | reconciliation table: staging = analytics (1800 rows, £2,480,524.12) |
| 5–12 | `05` … `12` | analysis outputs |
| 13 | `13_validate_ai_findings.sql` | AGREES / DIFFERS table |

Note: when a script has several queries, pgAdmin only shows the result of the last one. To see a specific query, highlight it and press F5.

The outputs should match the files in `results/`.

## 5. Inspect the model
Refresh the tree (right-click **Schemas** → Refresh):
* `staging` → raw TEXT tables
* `analytics` → `dim_*`, `fact_sales`, `fact_complaints`, `shopper_appeal`, view `vw_weakest_product`
* Right-click `analytics` → **ERD For Schema** shows the star-schema diagram (pgAdmin 6+).

## Alternative load: psql `\copy`
`02b_load_data_psql_copy.sql` uses `\copy`, which works in **pgAdmin → Tools → PSQL Tool** or Terminal, **not** in the Query Tool. Run it from the repo root:
```bash
cd ~/sql/retail-revenue-sql-analysis
psql -U postgres -d retail_analytics -f sql/02b_load_data_psql_copy.sql
```

## Troubleshooting
| Problem | Fix |
|---------|-----|
| `database "retail_analytics" is being accessed by other users` when re-running 00 | Close Query Tool tabs open on that DB, or right-click DB → Disconnect |
| `relation "staging.sales_weekly_raw" does not exist` | Run `01` before `02` |
| `relation "analytics.vw_weakest_product" does not exist` in 11/12/13 | Run `10` first (it creates that view) |
| `psql: command not found` on Mac | Use the full path, e.g. `/Library/PostgreSQL/16/bin/psql`, or add it to your PATH |
