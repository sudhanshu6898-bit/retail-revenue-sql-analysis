-- =====================================================================
-- STEP 02 (ALTERNATIVE) - Fast load with psql \copy
-- Use this INSTEAD of 02_load_data.sql if you prefer the command line
-- or pgAdmin's PSQL Tool (Tools > PSQL Tool). Run from the REPO ROOT:
--     psql -d retail_analytics -f sql/02b_load_data_psql_copy.sql
-- =====================================================================
TRUNCATE staging.sales_weekly_raw, staging.shopper_profile_raw,
         staging.variable_definitions_raw, staging.customer_complaints_raw;

\copy staging.sales_weekly_raw         FROM 'data/csv/sales_weekly.csv'           WITH (FORMAT csv, HEADER true)
\copy staging.shopper_profile_raw      FROM 'data/csv/shopper_profile_appeal.csv' WITH (FORMAT csv, HEADER true)
\copy staging.variable_definitions_raw FROM 'data/csv/variable_definitions.csv'   WITH (FORMAT csv, HEADER true)
\copy staging.customer_complaints_raw  FROM 'data/csv/customer_complaints.csv'    WITH (FORMAT csv, HEADER true)

SELECT 'sales_weekly_raw' AS table_name, COUNT(*) FROM staging.sales_weekly_raw
UNION ALL SELECT 'shopper_profile_raw', COUNT(*) FROM staging.shopper_profile_raw
UNION ALL SELECT 'variable_definitions_raw', COUNT(*) FROM staging.variable_definitions_raw
UNION ALL SELECT 'customer_complaints_raw', COUNT(*) FROM staging.customer_complaints_raw;
