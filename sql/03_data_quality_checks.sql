-- =====================================================================
-- STEP 03 - Data quality profiling on the RAW staging data
-- Run each check and review the output before cleaning (step 04).
-- =====================================================================

-- 3.1 Row counts per staging table
SELECT 'sales_weekly_raw' AS table_name, COUNT(*) AS row_count FROM staging.sales_weekly_raw
UNION ALL SELECT 'shopper_profile_raw',      COUNT(*) FROM staging.shopper_profile_raw
UNION ALL SELECT 'variable_definitions_raw', COUNT(*) FROM staging.variable_definitions_raw
UNION ALL SELECT 'customer_complaints_raw',  COUNT(*) FROM staging.customer_complaints_raw;

-- 3.2 Missing / blank values in key and measure columns (sales)
SELECT
    COUNT(*) FILTER (WHERE NULLIF(TRIM(week_start), '')            IS NULL) AS missing_week_start,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(store_id), '')              IS NULL) AS missing_store_id,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(channel), '')               IS NULL) AS missing_channel,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(product_group), '')         IS NULL) AS missing_product_group,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(last_year_sales_value), '') IS NULL) AS missing_ly_sales,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(current_sales_value), '')   IS NULL) AS missing_cy_sales,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(current_units), '')         IS NULL) AS missing_cy_units,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(current_customers), '')     IS NULL) AS missing_cy_customers
FROM staging.sales_weekly_raw;

-- 3.3 Duplicate check on the table grain (week x store x channel x product)
SELECT week_start, store_id, channel, tpn, COUNT(*) AS dup_count
FROM staging.sales_weekly_raw
GROUP BY week_start, store_id, channel, tpn
HAVING COUNT(*) > 1;            -- expect 0 rows

-- 3.4 Fully duplicated rows
SELECT COUNT(*) - COUNT(DISTINCT s.*) AS exact_duplicate_rows
FROM staging.sales_weekly_raw s;

-- 3.5 Distinct values per dimension (spot typos, casing, stray spaces)
SELECT 'week_start' AS column_name, COUNT(DISTINCT week_start) AS distinct_values FROM staging.sales_weekly_raw
UNION ALL SELECT 'month',              COUNT(DISTINCT month)              FROM staging.sales_weekly_raw
UNION ALL SELECT 'store_id',           COUNT(DISTINCT store_id)           FROM staging.sales_weekly_raw
UNION ALL SELECT 'store_name',         COUNT(DISTINCT store_name)         FROM staging.sales_weekly_raw
UNION ALL SELECT 'region',             COUNT(DISTINCT region)             FROM staging.sales_weekly_raw
UNION ALL SELECT 'channel',            COUNT(DISTINCT channel)            FROM staging.sales_weekly_raw
UNION ALL SELECT 'product_group',      COUNT(DISTINCT product_group)      FROM staging.sales_weekly_raw
UNION ALL SELECT 'product_group_code', COUNT(DISTINCT product_group_code) FROM staging.sales_weekly_raw
UNION ALL SELECT 'tpn',                COUNT(DISTINCT tpn)                FROM staging.sales_weekly_raw;

SELECT channel, COUNT(*) AS rows FROM staging.sales_weekly_raw GROUP BY channel ORDER BY channel;
SELECT store_id, store_name, COUNT(*) AS rows FROM staging.sales_weekly_raw GROUP BY 1, 2 ORDER BY 1;

-- 3.6 Leading / trailing whitespace in text columns
SELECT
    COUNT(*) FILTER (WHERE store_name    <> TRIM(store_name))    AS store_name_untrimmed,
    COUNT(*) FILTER (WHERE channel       <> TRIM(channel))       AS channel_untrimmed,
    COUNT(*) FILTER (WHERE product_group <> TRIM(product_group)) AS product_group_untrimmed,
    COUNT(*) FILTER (WHERE product_name  <> TRIM(product_name))  AS product_name_untrimmed
FROM staging.sales_weekly_raw;

-- 3.7 Type validation: values that would FAIL to cast (expect 0 everywhere)
SELECT
    COUNT(*) FILTER (WHERE week_start !~ '^\d{4}-\d{2}-\d{2}$')                    AS bad_dates,
    COUNT(*) FILTER (WHERE last_year_sales_value !~ '^-?\d+(\.\d+)?$')             AS bad_ly_sales,
    COUNT(*) FILTER (WHERE current_sales_value   !~ '^-?\d+(\.\d+)?$')             AS bad_cy_sales,
    COUNT(*) FILTER (WHERE current_units         !~ '^\d+$')                       AS bad_cy_units,
    COUNT(*) FILTER (WHERE current_customers     !~ '^\d+$')                       AS bad_cy_customers,
    COUNT(*) FILTER (WHERE sales_pct_change      !~ '^-?\d+(\.\d+)?([eE]-?\d+)?$') AS bad_pct_change
FROM staging.sales_weekly_raw;

-- 3.8 Range checks: negative or zero values where they make no sense
SELECT
    COUNT(*) FILTER (WHERE current_sales_value::NUMERIC   <= 0) AS non_positive_cy_sales,
    COUNT(*) FILTER (WHERE last_year_sales_value::NUMERIC <= 0) AS non_positive_ly_sales,
    COUNT(*) FILTER (WHERE current_units::INT             <= 0) AS non_positive_units,
    COUNT(*) FILTER (WHERE acv_weighted_distribution::NUMERIC NOT BETWEEN 0 AND 1) AS distribution_out_of_range,
    COUNT(*) FILTER (WHERE repeat_rate::NUMERIC              NOT BETWEEN 0 AND 1) AS repeat_rate_out_of_range
FROM staging.sales_weekly_raw;

-- 3.9 Reconcile derived columns against their source columns
SELECT
    COUNT(*) FILTER (WHERE ABS(sales_gap::NUMERIC
                     - (current_sales_value::NUMERIC - last_year_sales_value::NUMERIC)) > 0.01)      AS sales_gap_mismatch,
    COUNT(*) FILTER (WHERE ABS(sales_pct_change::NUMERIC
                     - (current_sales_value::NUMERIC / last_year_sales_value::NUMERIC - 1)) > 0.0001) AS sales_pct_mismatch,
    COUNT(*) FILTER (WHERE ABS(units_pct_change::NUMERIC
                     - (current_units::NUMERIC / last_year_units::NUMERIC - 1)) > 0.0001)             AS units_pct_mismatch,
    COUNT(*) FILTER (WHERE ABS(current_price_index::NUMERIC
                     - current_sales_value::NUMERIC / current_units::NUMERIC) > 0.01)                 AS price_index_mismatch,
    COUNT(*) FILTER (WHERE ABS(sales_per_store_current::NUMERIC
                     - current_sales_value::NUMERIC / stores_selling::NUMERIC) > 0.01)                AS sales_per_store_mismatch
FROM staging.sales_weekly_raw;

-- 3.10 Business-logic check: more unique customers than shopping visits
--      is not possible; these rows are flagged in step 04
SELECT week_start, store_name, channel, product_group,
       current_visits::INT AS visits, current_customers::INT AS customers
FROM staging.sales_weekly_raw
WHERE current_customers::INT > current_visits::INT
ORDER BY week_start, store_name;

-- 3.11 Consistency: one product group <-> one code <-> one TPN?
SELECT product_group,
       COUNT(DISTINCT product_group_code) AS codes,
       COUNT(DISTINCT tpn)                AS tpns,
       COUNT(DISTINCT product_name)       AS product_names,
       MIN(product_group_code)            AS product_group_code,
       MIN(tpn)                           AS tpn
FROM staging.sales_weekly_raw
GROUP BY product_group
ORDER BY product_group;

-- 3.12 TPN embeds a group code (TPN-<code>-nnn). Does it match the group code?
SELECT DISTINCT product_group, product_group_code, tpn,
       SPLIT_PART(tpn, '-', 2) AS code_inside_tpn
FROM staging.sales_weekly_raw
WHERE SPLIT_PART(tpn, '-', 2) <> product_group_code
ORDER BY product_group;

-- 3.13 Shopper profile sheet contains a TOTAL row that must not be treated as a product
SELECT product_group, product_group_code
FROM staging.shopper_profile_raw
WHERE product_group_code IS NULL;

-- 3.14 Complaints: date format, blanks, value domains
SELECT
    COUNT(*)                                                               AS total_rows,
    COUNT(*) FILTER (WHERE complaint_date !~ '^\d{2}/\d{2}/\d{4}$')        AS non_ddmmyyyy_dates,
    COUNT(*) FILTER (WHERE severity_1_to_5 !~ '^[1-5]$')                   AS bad_severity,
    COUNT(*) FILTER (WHERE repeat_complaint_flag NOT IN ('Yes', 'No'))     AS bad_repeat_flag,
    COUNT(DISTINCT complaint_id)                                           AS distinct_ids
FROM staging.customer_complaints_raw;

-- 3.15 Complaint product groups that do not exist in the sales data
SELECT DISTINCT c.product_group
FROM staging.customer_complaints_raw c
LEFT JOIN (SELECT DISTINCT product_group FROM staging.sales_weekly_raw) s
       ON UPPER(TRIM(c.product_group)) = UPPER(TRIM(s.product_group))
WHERE s.product_group IS NULL;
