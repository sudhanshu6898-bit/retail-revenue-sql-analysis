-- =====================================================================
-- STEP 01 - Create schemas and RAW staging tables
-- Database: retail_analytics
--
-- Design: a two-layer warehouse
--   staging   -> raw data as received, all columns TEXT
--   analytics -> cleaned, typed, constrained star schema (step 04)
-- =====================================================================
DROP SCHEMA IF EXISTS staging CASCADE;
CREATE SCHEMA staging;

-- 1) Weekly sales: one row per week x store x channel x product group
CREATE TABLE staging.sales_weekly_raw (
    week_start                          TEXT,
    month                               TEXT,
    store_id                            TEXT,
    store_name                          TEXT,
    region                              TEXT,
    channel                             TEXT,
    product_group                       TEXT,
    product_group_code                  TEXT,
    tpn                                 TEXT,
    product_name                        TEXT,
    customer_lifestage                  TEXT,
    lifestyle_segment                   TEXT,
    last_year_sales_value               TEXT,
    current_sales_value                 TEXT,
    sales_gap                           TEXT,
    sales_pct_change                    TEXT,
    last_year_units                     TEXT,
    current_units                       TEXT,
    units_pct_change                    TEXT,
    last_year_visits                    TEXT,
    current_visits                      TEXT,
    visits_pct_change                   TEXT,
    last_year_customers                 TEXT,
    current_customers                   TEXT,
    customers_pct_change                TEXT,
    last_year_price_index               TEXT,
    current_price_index                 TEXT,
    price_index_pct_change              TEXT,
    acv_weighted_distribution           TEXT,
    acv_weighted_distribution_pct_change TEXT,
    basket_penetration                  TEXT,
    category_share_spend                TEXT,
    repeat_rate                         TEXT,
    stores_selling                      TEXT,
    sales_per_store_current             TEXT,
    price_effect_pct_change             TEXT,
    competitor_price_index              TEXT
);

-- 2) Shopper appeal index (100 = average appeal) by product group
CREATE TABLE staging.shopper_profile_raw (
    product_group       TEXT,
    product_group_code  TEXT,
    young_adults        TEXT,
    young_families      TEXT,
    older_families      TEXT,
    older_adults        TEXT,
    pensioners          TEXT,
    convenience         TEXT,
    finer_foods         TEXT,
    kids_choice         TEXT,
    mainstream          TEXT,
    price_sensitive     TEXT,
    traditional         TEXT
);

-- 3) Data dictionary supplied with the dataset
CREATE TABLE staging.variable_definitions_raw (
    variable    TEXT,
    definition  TEXT
);

-- 4) Customer complaints (second dataset)
CREATE TABLE staging.customer_complaints_raw (
    complaint_id                    TEXT,
    complaint_date                  TEXT,
    region                          TEXT,
    product_group                   TEXT,
    customer_segment                TEXT,
    complaint_channel               TEXT,
    complaint_theme                 TEXT,
    customer_complaint              TEXT,
    current_digital_content_problem TEXT,
    customer_expectation            TEXT,
    severity_1_to_5                 TEXT,
    customer_sentiment              TEXT,
    repeat_complaint_flag           TEXT,
    linked_business_problem         TEXT
);
