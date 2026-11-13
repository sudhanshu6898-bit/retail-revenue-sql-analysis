-- =====================================================================
-- STEP 10 - Deep dive: the WEAKEST product line (identified in step 07)
-- =====================================================================

-- 10.1 View that returns the weakest product group
CREATE OR REPLACE VIEW analytics.vw_weakest_product AS
SELECT p.tpn, p.product_group, p.product_name,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 2) AS revenue_yoy_pct
FROM analytics.fact_sales f
JOIN analytics.dim_product p USING (tpn)
GROUP BY p.tpn, p.product_group, p.product_name
ORDER BY SUM(f.cy_sales_value) / SUM(f.ly_sales_value)
LIMIT 1;

SELECT * FROM analytics.vw_weakest_product;

-- 10.2 Weakest line vs the rest of the business (side-by-side KPIs)
SELECT CASE WHEN f.tpn = w.tpn THEN w.product_group ELSE 'ALL OTHER GROUPS' END AS segment,
       SUM(f.cy_sales_value)                                                     AS cy_revenue,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1)    AS revenue_yoy_pct,
       ROUND(100.0 * (SUM(f.cy_units)::NUMERIC / SUM(f.ly_units) - 1), 1)       AS units_yoy_pct,
       ROUND(100.0 * (SUM(f.cy_customers)::NUMERIC / SUM(f.ly_customers) - 1), 1) AS customers_yoy_pct,
       ROUND(100.0 * ((SUM(f.cy_sales_value) / SUM(f.cy_units))
                    / (SUM(f.ly_sales_value) / SUM(f.ly_units)) - 1), 1)        AS avg_price_change_pct,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.competitor_avg_price * f.cy_units) - 1), 1) AS premium_vs_competitor_pct,
       ROUND(100.0 * AVG(f.acv_distribution), 1)                                 AS avg_distribution_pct,
       ROUND(100.0 * AVG(f.repeat_rate), 1)                                      AS avg_repeat_rate_pct
FROM analytics.fact_sales f
CROSS JOIN analytics.vw_weakest_product w
GROUP BY 1
ORDER BY 1;

-- 10.3 Monthly trend of the weakest line: price, competitor price, units
SELECT d.month_label,
       SUM(f.cy_sales_value)                                                  AS cy_revenue,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1) AS revenue_yoy_pct,
       ROUND(100.0 * (SUM(f.cy_units)::NUMERIC / SUM(f.ly_units) - 1), 1)    AS units_yoy_pct,
       ROUND(SUM(f.cy_sales_value) / SUM(f.cy_units), 2)                      AS our_avg_price,
       ROUND(SUM(f.competitor_avg_price * f.cy_units) / SUM(f.cy_units), 2)   AS competitor_price,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.competitor_avg_price * f.cy_units) - 1), 1) AS premium_vs_competitor_pct
FROM analytics.fact_sales f
JOIN analytics.vw_weakest_product w USING (tpn)
JOIN analytics.dim_date d USING (date_key)
GROUP BY d.week_start, d.month_label
ORDER BY d.week_start;

-- 10.4 Weakest line by channel
SELECT c.channel_name,
       SUM(f.cy_sales_value)                                                  AS cy_revenue,
       SUM(f.sales_gap)                                                       AS revenue_gap,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1) AS revenue_yoy_pct,
       ROUND(100.0 * (SUM(f.cy_units)::NUMERIC / SUM(f.ly_units) - 1), 1)    AS units_yoy_pct
FROM analytics.fact_sales f
JOIN analytics.vw_weakest_product w USING (tpn)
JOIN analytics.dim_channel c USING (channel_id)
GROUP BY c.channel_name
ORDER BY revenue_yoy_pct;

-- 10.5 Weakest line by store (ranked)
SELECT s.store_name,
       SUM(f.cy_sales_value)                                                  AS cy_revenue,
       SUM(f.sales_gap)                                                       AS revenue_gap,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1) AS revenue_yoy_pct,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.competitor_avg_price * f.cy_units) - 1), 1) AS premium_vs_competitor_pct,
       RANK() OVER (ORDER BY SUM(f.cy_sales_value) / SUM(f.ly_sales_value))   AS worst_rank
FROM analytics.fact_sales f
JOIN analytics.vw_weakest_product w USING (tpn)
JOIN analytics.dim_store s USING (store_id)
GROUP BY s.store_name
ORDER BY worst_rank;

-- 10.6 Price sensitivity: units change by price premium quartile, plus regression
WITH x AS (
    SELECT f.*,
           f.cy_avg_price / f.competitor_avg_price - 1 AS premium,
           f.cy_units::NUMERIC / f.ly_units - 1        AS units_chg
    FROM analytics.fact_sales f
    JOIN analytics.vw_weakest_product w USING (tpn)
)
SELECT NTILE(4) OVER (ORDER BY premium)                    AS premium_quartile,
       premium, units_chg
INTO TEMP TABLE weakest_premium_buckets
FROM x;

SELECT premium_quartile,
       COUNT(*)                                  AS records,
       ROUND(100.0 * MIN(premium), 1)            AS min_premium_pct,
       ROUND(100.0 * MAX(premium), 1)            AS max_premium_pct,
       ROUND(100.0 * AVG(units_chg), 1)          AS avg_units_change_pct
FROM weakest_premium_buckets
GROUP BY premium_quartile
ORDER BY premium_quartile;

SELECT ROUND(CORR(units_chg, premium)::NUMERIC, 3)        AS corr_units_vs_premium,
       ROUND(REGR_SLOPE(units_chg, premium)::NUMERIC, 2)  AS units_pts_lost_per_1pt_premium,
       ROUND(REGR_R2(units_chg, premium)::NUMERIC, 3)     AS r_squared
FROM weakest_premium_buckets;

DROP TABLE weakest_premium_buckets;

-- 10.7 What-if: revenue if the weakest line matched the competitor's price
--      and recovered half of its lost units (scenario only)
WITH base AS (
    SELECT SUM(f.cy_units)                   AS cy_units,
           SUM(f.ly_units)                   AS ly_units,
           SUM(f.cy_sales_value)             AS cy_revenue,
           SUM(f.competitor_avg_price * f.cy_units) / SUM(f.cy_units) AS competitor_price  -- unit-weighted
    FROM analytics.fact_sales f
    JOIN analytics.vw_weakest_product w USING (tpn)
)
SELECT cy_revenue                                                   AS current_revenue,
       ROUND(competitor_price, 2)                                   AS new_price_matched_to_competitor,
       cy_units + (ly_units - cy_units) / 2                         AS scenario_units,
       ROUND((cy_units + (ly_units - cy_units) / 2) * competitor_price, 2)              AS scenario_revenue,
       ROUND((cy_units + (ly_units - cy_units) / 2) * competitor_price - cy_revenue, 2) AS scenario_uplift
FROM base;
