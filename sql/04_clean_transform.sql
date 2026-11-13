-- =====================================================================
-- STEP 04 - Clean, type and model the data into a STAR SCHEMA
--
--   analytics.dim_date      one row per reporting week
--   analytics.dim_store     10 stores
--   analytics.dim_channel   3 channels
--   analytics.dim_product   10 product groups (one TPN each)
--   analytics.fact_sales    1,800 rows: week x store x channel x product
--   analytics.shopper_appeal   unpivoted shopper appeal index
--   analytics.fact_complaints  600 customer complaints
--
-- Cleaning rules applied (all found in step 03):
--   * TRIM every text field, standardise casing of product groups
--   * Cast TEXT -> DATE / INT / NUMERIC with correct precision
--   * Convert complaint dates from DD/MM/YYYY text to DATE
--   * Yes/No flags -> BOOLEAN
--   * Remove the "Category shopper appeal" TOTAL row from the profile sheet
--   * Flag (not delete) rows where customers > visits  (dq_customers_gt_visits)
--   * Keep TPN as-is but flag where its embedded code differs (dq_tpn_code_mismatch)
--   * CHECK constraints so bad data can never be inserted again
-- =====================================================================
DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

-- ---------------------------------------------------------------------
-- 4.1 Dimensions
-- ---------------------------------------------------------------------
CREATE TABLE analytics.dim_date (
    date_key     INT PRIMARY KEY,                 -- yyyymmdd
    week_start   DATE NOT NULL UNIQUE,
    month_label  TEXT NOT NULL,                   -- e.g. Jan-2026
    month_num    INT  NOT NULL CHECK (month_num BETWEEN 1 AND 12),
    quarter_num  INT  NOT NULL CHECK (quarter_num BETWEEN 1 AND 4),
    year_num     INT  NOT NULL
);

INSERT INTO analytics.dim_date
SELECT DISTINCT
    TO_CHAR(TRIM(week_start)::DATE, 'YYYYMMDD')::INT,
    TRIM(week_start)::DATE,
    TRIM(month),
    EXTRACT(MONTH   FROM TRIM(week_start)::DATE)::INT,
    EXTRACT(QUARTER FROM TRIM(week_start)::DATE)::INT,
    EXTRACT(YEAR    FROM TRIM(week_start)::DATE)::INT
FROM staging.sales_weekly_raw;

CREATE TABLE analytics.dim_store (
    store_id    TEXT PRIMARY KEY,
    store_name  TEXT NOT NULL UNIQUE,
    region      TEXT NOT NULL
);

INSERT INTO analytics.dim_store
SELECT DISTINCT TRIM(store_id), TRIM(store_name), TRIM(region)
FROM staging.sales_weekly_raw;

CREATE TABLE analytics.dim_channel (
    channel_id    SERIAL PRIMARY KEY,
    channel_name  TEXT NOT NULL UNIQUE,
    is_online     BOOLEAN NOT NULL
);

INSERT INTO analytics.dim_channel (channel_name, is_online)
SELECT DISTINCT TRIM(channel), TRIM(channel) <> 'Store'
FROM staging.sales_weekly_raw
ORDER BY 1;

CREATE TABLE analytics.dim_product (
    tpn                   TEXT PRIMARY KEY,
    product_name          TEXT NOT NULL,
    product_group         TEXT NOT NULL UNIQUE,
    product_group_code    TEXT NOT NULL UNIQUE,
    customer_lifestage    TEXT NOT NULL,
    lifestyle_segment     TEXT NOT NULL,
    dq_tpn_code_mismatch  BOOLEAN NOT NULL       -- TPN code <> group code (source labelling issue)
);

-- A product's lifestage/segment can vary by row in the source, so take the
-- MOST FREQUENT value per product (MODE) as its primary target shopper.
INSERT INTO analytics.dim_product
SELECT
    TRIM(tpn),
    MIN(TRIM(product_name)),
    UPPER(MIN(TRIM(product_group))),
    MIN(TRIM(product_group_code)),
    MODE() WITHIN GROUP (ORDER BY TRIM(customer_lifestage)),
    MODE() WITHIN GROUP (ORDER BY TRIM(lifestyle_segment)),
    SPLIT_PART(TRIM(tpn), '-', 2) <> MIN(TRIM(product_group_code))
FROM staging.sales_weekly_raw
GROUP BY TRIM(tpn);

-- ---------------------------------------------------------------------
-- 4.2 Fact table
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_sales (
    sales_id                    BIGSERIAL PRIMARY KEY,
    date_key                    INT  NOT NULL REFERENCES analytics.dim_date(date_key),
    store_id                    TEXT NOT NULL REFERENCES analytics.dim_store(store_id),
    channel_id                  INT  NOT NULL REFERENCES analytics.dim_channel(channel_id),
    tpn                         TEXT NOT NULL REFERENCES analytics.dim_product(tpn),
    customer_lifestage          TEXT NOT NULL,
    lifestyle_segment           TEXT NOT NULL,
    -- revenue (GBP)
    ly_sales_value              NUMERIC(12,2) NOT NULL CHECK (ly_sales_value >= 0),
    cy_sales_value              NUMERIC(12,2) NOT NULL CHECK (cy_sales_value >= 0),
    -- volume & traffic
    ly_units                    INT NOT NULL CHECK (ly_units >= 0),
    cy_units                    INT NOT NULL CHECK (cy_units >= 0),
    ly_visits                   INT NOT NULL CHECK (ly_visits >= 0),
    cy_visits                   INT NOT NULL CHECK (cy_visits >= 0),
    ly_customers                INT NOT NULL CHECK (ly_customers >= 0),
    cy_customers                INT NOT NULL CHECK (cy_customers >= 0),
    -- price (average selling price per unit, GBP)
    ly_avg_price                NUMERIC(10,4) NOT NULL,
    cy_avg_price                NUMERIC(10,4) NOT NULL,
    competitor_avg_price        NUMERIC(10,4) NOT NULL,
    price_effect_pct_change     NUMERIC(10,6),
    -- distribution & loyalty
    acv_distribution            NUMERIC(8,6) NOT NULL CHECK (acv_distribution BETWEEN 0 AND 1),
    acv_distribution_pct_change NUMERIC(10,6),
    basket_penetration          NUMERIC(10,6),
    category_share_spend        NUMERIC(10,6),
    repeat_rate                 NUMERIC(8,6) CHECK (repeat_rate BETWEEN 0 AND 1),
    stores_selling              INT,
    -- derived (stored so every query uses one consistent definition)
    sales_gap                   NUMERIC(12,2) GENERATED ALWAYS AS (cy_sales_value - ly_sales_value) STORED,
    -- data-quality flag
    dq_customers_gt_visits      BOOLEAN GENERATED ALWAYS AS (cy_customers > cy_visits) STORED,
    UNIQUE (date_key, store_id, channel_id, tpn)          -- enforce the grain
);

INSERT INTO analytics.fact_sales (
    date_key, store_id, channel_id, tpn, customer_lifestage, lifestyle_segment,
    ly_sales_value, cy_sales_value, ly_units, cy_units, ly_visits, cy_visits,
    ly_customers, cy_customers, ly_avg_price, cy_avg_price, competitor_avg_price,
    price_effect_pct_change, acv_distribution, acv_distribution_pct_change,
    basket_penetration, category_share_spend, repeat_rate, stores_selling)
SELECT
    TO_CHAR(TRIM(r.week_start)::DATE, 'YYYYMMDD')::INT,
    TRIM(r.store_id),
    c.channel_id,
    TRIM(r.tpn),
    TRIM(r.customer_lifestage),
    TRIM(r.lifestyle_segment),
    r.last_year_sales_value::NUMERIC,
    r.current_sales_value::NUMERIC,
    r.last_year_units::INT,
    r.current_units::INT,
    r.last_year_visits::INT,
    r.current_visits::INT,
    r.last_year_customers::INT,
    r.current_customers::INT,
    r.last_year_price_index::NUMERIC,
    r.current_price_index::NUMERIC,
    r.competitor_price_index::NUMERIC,
    r.price_effect_pct_change::NUMERIC,
    r.acv_weighted_distribution::NUMERIC,
    r.acv_weighted_distribution_pct_change::NUMERIC,
    r.basket_penetration::NUMERIC,
    r.category_share_spend::NUMERIC,
    r.repeat_rate::NUMERIC,
    r.stores_selling::INT
FROM staging.sales_weekly_raw r
JOIN analytics.dim_channel c ON c.channel_name = TRIM(r.channel);

CREATE INDEX ix_fact_sales_date    ON analytics.fact_sales(date_key);
CREATE INDEX ix_fact_sales_store   ON analytics.fact_sales(store_id);
CREATE INDEX ix_fact_sales_channel ON analytics.fact_sales(channel_id);
CREATE INDEX ix_fact_sales_tpn     ON analytics.fact_sales(tpn);

-- ---------------------------------------------------------------------
-- 4.3 Shopper appeal: wide sheet -> long table (UNPIVOT), total row removed
-- ---------------------------------------------------------------------
CREATE TABLE analytics.shopper_appeal (
    product_group  TEXT NOT NULL REFERENCES analytics.dim_product(product_group),
    segment_type   TEXT NOT NULL CHECK (segment_type IN ('Lifestage', 'Lifestyle')),
    segment        TEXT NOT NULL,
    appeal_index   NUMERIC(6,1) NOT NULL,          -- 100 = average appeal
    PRIMARY KEY (product_group, segment)
);

INSERT INTO analytics.shopper_appeal
SELECT UPPER(TRIM(p.product_group)), v.segment_type, v.segment, v.idx::NUMERIC
FROM staging.shopper_profile_raw p
CROSS JOIN LATERAL (VALUES
    ('Lifestage', 'Young Adults',    p.young_adults),
    ('Lifestage', 'Young Families',  p.young_families),
    ('Lifestage', 'Older Families',  p.older_families),
    ('Lifestage', 'Older Adults',    p.older_adults),
    ('Lifestage', 'Pensioners',      p.pensioners),
    ('Lifestyle', 'Convenience',     p.convenience),
    ('Lifestyle', 'Finer Foods',     p.finer_foods),
    ('Lifestyle', 'Kids Choice',     p.kids_choice),
    ('Lifestyle', 'Mainstream',      p.mainstream),
    ('Lifestyle', 'Price Sensitive', p.price_sensitive),
    ('Lifestyle', 'Traditional',     p.traditional)
) AS v(segment_type, segment, idx)
WHERE p.product_group_code IS NOT NULL;        -- drop "Category shopper appeal" total row

-- ---------------------------------------------------------------------
-- 4.4 Customer complaints
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_complaints (
    complaint_id             TEXT PRIMARY KEY,
    complaint_date           DATE NOT NULL,
    region                   TEXT NOT NULL,
    product_group            TEXT NOT NULL REFERENCES analytics.dim_product(product_group),
    customer_segment         TEXT NOT NULL,
    complaint_channel        TEXT NOT NULL,
    complaint_theme          TEXT NOT NULL,
    customer_complaint       TEXT,
    digital_content_problem  TEXT,
    customer_expectation     TEXT,
    severity                 SMALLINT NOT NULL CHECK (severity BETWEEN 1 AND 5),
    customer_sentiment       TEXT NOT NULL,
    is_repeat_complaint      BOOLEAN NOT NULL,
    linked_business_problem  TEXT
);

INSERT INTO analytics.fact_complaints
SELECT
    TRIM(complaint_id),
    TO_DATE(TRIM(complaint_date), 'DD/MM/YYYY'),
    TRIM(region),
    UPPER(TRIM(product_group)),
    TRIM(customer_segment),
    TRIM(complaint_channel),
    TRIM(complaint_theme),
    TRIM(customer_complaint),
    TRIM(current_digital_content_problem),
    TRIM(customer_expectation),
    severity_1_to_5::SMALLINT,
    TRIM(customer_sentiment),
    TRIM(repeat_complaint_flag) = 'Yes',
    TRIM(linked_business_problem)
FROM staging.customer_complaints_raw;

-- ---------------------------------------------------------------------
-- 4.5 Data dictionary (kept for documentation)
-- ---------------------------------------------------------------------
CREATE TABLE analytics.data_dictionary AS
SELECT TRIM(variable) AS variable, TRIM(definition) AS definition
FROM staging.variable_definitions_raw;

-- ---------------------------------------------------------------------
-- 4.6 Post-load reconciliation: staging totals must equal analytics totals
-- ---------------------------------------------------------------------
SELECT 'row count' AS check_name,
       (SELECT COUNT(*) FROM staging.sales_weekly_raw)::NUMERIC AS staging_value,
       (SELECT COUNT(*) FROM analytics.fact_sales)::NUMERIC     AS analytics_value
UNION ALL
SELECT 'current sales £',
       (SELECT SUM(current_sales_value::NUMERIC) FROM staging.sales_weekly_raw),
       (SELECT SUM(cy_sales_value) FROM analytics.fact_sales)
UNION ALL
SELECT 'last year sales £',
       (SELECT SUM(last_year_sales_value::NUMERIC) FROM staging.sales_weekly_raw),
       (SELECT SUM(ly_sales_value) FROM analytics.fact_sales)
UNION ALL
SELECT 'current units',
       (SELECT SUM(current_units::INT) FROM staging.sales_weekly_raw),
       (SELECT SUM(cy_units) FROM analytics.fact_sales)
UNION ALL
SELECT 'complaints',
       (SELECT COUNT(*) FROM staging.customer_complaints_raw),
       (SELECT COUNT(*) FROM analytics.fact_complaints)
UNION ALL
SELECT 'shopper appeal rows (10 groups x 11 segments)',
       110, (SELECT COUNT(*) FROM analytics.shopper_appeal);

-- Rows carrying data-quality flags
SELECT
    COUNT(*) FILTER (WHERE dq_customers_gt_visits)  AS rows_customers_gt_visits,
    (SELECT COUNT(*) FROM analytics.dim_product WHERE dq_tpn_code_mismatch) AS products_tpn_code_mismatch
FROM analytics.fact_sales;
