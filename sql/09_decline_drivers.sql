-- =====================================================================
-- STEP 09 - Drivers of the revenue decline
--
--   Revenue = Units x Average price
--   Units   = Customers x Units per customer
--
-- 9.1 splits the £ gap exactly into a VOLUME effect and a PRICE effect:
--   volume effect = (CY units - LY units) x LY price
--   price  effect = (CY price - LY price) x CY units
--   volume + price = CY revenue - LY revenue
-- =====================================================================

-- 9.1 Price / volume decomposition by product group
WITH pg AS (
    SELECT p.product_group,
           SUM(f.ly_sales_value) AS ly_rev, SUM(f.cy_sales_value) AS cy_rev,
           SUM(f.ly_units)       AS ly_units, SUM(f.cy_units)     AS cy_units
    FROM analytics.fact_sales f
    JOIN analytics.dim_product p USING (tpn)
    GROUP BY p.product_group
)
SELECT product_group,
       ROUND(cy_rev - ly_rev, 2)                                         AS revenue_gap,
       ROUND((cy_units - ly_units) * (ly_rev / ly_units), 2)             AS volume_effect,
       ROUND((cy_rev / cy_units - ly_rev / ly_units) * cy_units, 2)      AS price_effect,
       ROUND(100.0 * ((cy_rev / cy_units) / (ly_rev / ly_units) - 1), 2) AS avg_price_change_pct,
       ROUND(100.0 * (cy_units::NUMERIC / ly_units - 1), 2)              AS units_change_pct,
       CASE WHEN cy_rev < ly_rev
             AND (cy_units - ly_units) * (ly_rev / ly_units) < 0
             AND (cy_rev / cy_units) > (ly_rev / ly_units)
            THEN 'Price up, volume down' END                             AS diagnosis
FROM pg
ORDER BY revenue_gap;

-- 9.2 Same decomposition for the whole business
SELECT ROUND(SUM(cy_sales_value) - SUM(ly_sales_value), 2)                                         AS revenue_gap,
       ROUND((SUM(cy_units) - SUM(ly_units)) * SUM(ly_sales_value) / SUM(ly_units), 2)             AS volume_effect,
       ROUND((SUM(cy_sales_value) / SUM(cy_units) - SUM(ly_sales_value) / SUM(ly_units)) * SUM(cy_units), 2) AS price_effect
FROM analytics.fact_sales;

-- 9.3 Volume split: fewer customers or fewer units per customer?
SELECT p.product_group,
       ROUND(100.0 * (SUM(f.cy_customers)::NUMERIC / SUM(f.ly_customers) - 1), 2) AS customers_change_pct,
       ROUND(100.0 * ((SUM(f.cy_units)::NUMERIC / SUM(f.cy_customers))
                    / (SUM(f.ly_units)::NUMERIC / SUM(f.ly_customers)) - 1), 2)    AS units_per_customer_change_pct,
       ROUND(100.0 * (SUM(f.cy_visits)::NUMERIC / SUM(f.ly_visits) - 1), 2)       AS visits_change_pct
FROM analytics.fact_sales f
JOIN analytics.dim_product p USING (tpn)
GROUP BY p.product_group
ORDER BY customers_change_pct;

-- 9.4 Our price vs the main competitor (price premium %)
--     Competitor price is UNIT-WEIGHTED so it is like-for-like with our
--     weighted average price (a plain AVG() would compare different mixes).
--     Note: the dataset holds one competitor price per record (current period),
--     so the LY premium compares our LY price to that same competitor price.
SELECT p.product_group,
       ROUND(SUM(f.ly_sales_value) / SUM(f.ly_units), 2)                                AS ly_our_price,
       ROUND(SUM(f.cy_sales_value) / SUM(f.cy_units), 2)                                AS cy_our_price,
       ROUND(SUM(f.competitor_avg_price * f.cy_units) / SUM(f.cy_units), 2)             AS competitor_price,
       ROUND(100.0 * (SUM(f.ly_sales_value) / SUM(f.competitor_avg_price * f.ly_units) - 1), 1) AS ly_premium_vs_competitor_pct,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.competitor_avg_price * f.cy_units) - 1), 1) AS cy_premium_vs_competitor_pct,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1)           AS revenue_yoy_pct,
       RANK() OVER (ORDER BY SUM(f.cy_sales_value) / SUM(f.competitor_avg_price * f.cy_units) DESC) AS premium_rank,
       RANK() OVER (ORDER BY SUM(f.cy_sales_value) / SUM(f.ly_sales_value))                       AS decline_rank
FROM analytics.fact_sales f
JOIN analytics.dim_product p USING (tpn)
GROUP BY p.product_group
ORDER BY cy_premium_vs_competitor_pct DESC;

-- 9.4b Correlation between price premium and revenue change across groups
WITH g AS (
    SELECT tpn,
           SUM(cy_sales_value) / SUM(competitor_avg_price * cy_units) - 1 AS premium,
           SUM(cy_sales_value) / SUM(ly_sales_value) - 1                  AS revenue_yoy
    FROM analytics.fact_sales
    GROUP BY tpn
)
SELECT ROUND(CORR(premium, revenue_yoy)::NUMERIC, 3) AS corr_premium_vs_revenue_yoy_across_groups
FROM g;

-- 9.5 Distribution and repeat rate by product group
SELECT p.product_group,
       ROUND(100.0 * AVG(f.acv_distribution), 1)             AS avg_acv_distribution_pct,
       ROUND(100.0 * AVG(f.acv_distribution_pct_change), 2)  AS avg_distribution_change_pct,
       ROUND(100.0 * AVG(f.repeat_rate), 1)                  AS avg_repeat_rate_pct,
       ROUND(100.0 * AVG(f.basket_penetration), 3)           AS avg_basket_penetration_pct,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1) AS revenue_yoy_pct
FROM analytics.fact_sales f
JOIN analytics.dim_product p USING (tpn)
GROUP BY p.product_group
ORDER BY revenue_yoy_pct;

-- 9.6 Correlation of each driver with revenue change (all 1,800 records)
--     (CORR = Pearson correlation with the record's revenue % change)
SELECT
    ROUND(CORR(cy_sales_value / ly_sales_value - 1, cy_avg_price / ly_avg_price - 1)::NUMERIC, 3)          AS corr_with_price_change,
    ROUND(CORR(cy_sales_value / ly_sales_value - 1, cy_avg_price / competitor_avg_price - 1)::NUMERIC, 3)  AS corr_with_premium_vs_competitor,
    ROUND(CORR(cy_sales_value / ly_sales_value - 1, acv_distribution_pct_change)::NUMERIC, 3)              AS corr_with_distribution_change,
    ROUND(CORR(cy_sales_value / ly_sales_value - 1, cy_customers::NUMERIC / ly_customers - 1)::NUMERIC, 3) AS corr_with_customer_change,
    ROUND(CORR(cy_sales_value / ly_sales_value - 1, repeat_rate)::NUMERIC, 3)                              AS corr_with_repeat_rate
FROM analytics.fact_sales;

-- 9.7 In-store vs online change by store
SELECT s.store_name,
       ROUND(100.0 * (SUM(f.cy_sales_value) FILTER (WHERE NOT c.is_online)
                    / SUM(f.ly_sales_value) FILTER (WHERE NOT c.is_online) - 1), 1) AS instore_yoy_pct,
       ROUND(100.0 * (SUM(f.cy_sales_value) FILTER (WHERE c.is_online)
                    / SUM(f.ly_sales_value) FILTER (WHERE c.is_online) - 1), 1)     AS online_yoy_pct,
       ROUND(100.0 * (SUM(f.cy_visits)::NUMERIC / SUM(f.ly_visits) - 1), 1)         AS visits_yoy_pct
FROM analytics.fact_sales f
JOIN analytics.dim_store   s USING (store_id)
JOIN analytics.dim_channel c USING (channel_id)
GROUP BY s.store_name
ORDER BY instore_yoy_pct;
