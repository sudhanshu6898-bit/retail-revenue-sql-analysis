-- =====================================================================
-- Run the whole pipeline end-to-end with psql (from the REPO ROOT):
--
--   psql -d postgres -f sql/00_create_database.sql
--   psql -d retail_analytics -f sql/run_all.sql
--
-- In pgAdmin instead: open each file in the Query Tool in number order
-- and press F5 (see docs/pgadmin_step_by_step.md).
-- =====================================================================
\set ON_ERROR_STOP on
\echo '== 01 staging tables'          \i sql/01_create_staging_tables.sql
\echo '== 02 load data'               \i sql/02_load_data.sql
\echo '== 03 data quality checks'     \i sql/03_data_quality_checks.sql
\echo '== 04 clean + star schema'     \i sql/04_clean_transform.sql
\echo '== 05 KPI overview'            \i sql/05_kpi_overview.sql
\echo '== 06 store ranking'           \i sql/06_store_ranking.sql
\echo '== 07 product group ranking'   \i sql/07_product_group_ranking.sql
\echo '== 08 channel ranking'         \i sql/08_channel_ranking.sql
\echo '== 09 decline drivers'         \i sql/09_decline_drivers.sql
\echo '== 10 weakest product'         \i sql/10_weakest_product_deep_dive.sql
\echo '== 11 shopper profile'         \i sql/11_shopper_profile_analysis.sql
\echo '== 12 customer complaints'     \i sql/12_customer_complaints_analysis.sql
\echo '== 13 validate AI findings'    \i sql/13_validate_ai_findings.sql
\echo '== DONE'
