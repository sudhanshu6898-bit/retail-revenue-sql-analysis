-- =====================================================================
-- STEP 05 - Headline KPIs: revenue, units, customers, visits, price,
--           distribution - current year (CY) vs last year (LY)
-- =====================================================================

-- 5.1 Business-level KPI summary
SELECT
    COUNT(*)                                                        AS records,
    COUNT(DISTINCT store_id)                                        AS stores,
    COUNT(DISTINCT tpn)                                             AS product_groups,
    COUNT(DISTINCT channel_id)                                      AS channels,
    SUM(ly_sales_value)                                             AS ly_revenue,
    SUM(cy_sales_value)                                             AS cy_revenue,
    SUM(sales_gap)                                                  AS revenue_gap,
    ROUND(100.0 * (SUM(cy_sales_value) / SUM(ly_sales_value) - 1), 2) AS revenue_yoy_pct,
    SUM(ly_units)                                                   AS ly_units,
    SUM(cy_units)                                                   AS cy_units,
    ROUND(100.0 * (SUM(cy_units)::NUMERIC / SUM(ly_units) - 1), 2)  AS units_yoy_pct,
    SUM(cy_customers)                                               AS cy_customers,
    ROUND(100.0 * (SUM(cy_customers)::NUMERIC / SUM(ly_customers) - 1), 2) AS customers_yoy_pct,
    ROUND(100.0 * (SUM(cy_visits)::NUMERIC / SUM(ly_visits) - 1), 2)       AS visits_yoy_pct,
    ROUND(SUM(ly_sales_value) / SUM(ly_units), 4)                   AS ly_avg_price,
    ROUND(SUM(cy_sales_value) / SUM(cy_units), 4)                   AS cy_avg_price,
    ROUND(100.0 * AVG(acv_distribution), 2)                         AS avg_acv_distribution_pct
FROM analytics.fact_sales;

-- 5.2 Monthly trend with month-on-month change (window function LAG)
WITH monthly AS (
    SELECT d.week_start, d.month_label,
           SUM(f.ly_sales_value) AS ly_revenue,
           SUM(f.cy_sales_value) AS cy_revenue,
           SUM(f.cy_units)       AS cy_units,
           SUM(f.cy_customers)   AS cy_customers
    FROM analytics.fact_sales f
    JOIN analytics.dim_date d USING (date_key)
    GROUP BY d.week_start, d.month_label
)
SELECT month_label,
       ly_revenue,
       cy_revenue,
       cy_revenue - ly_revenue                                          AS revenue_gap,
       ROUND(100.0 * (cy_revenue / ly_revenue - 1), 2)                  AS yoy_pct,
       ROUND(100.0 * (cy_revenue / LAG(cy_revenue) OVER (ORDER BY week_start) - 1), 2) AS mom_pct,
       SUM(cy_revenue) OVER (ORDER BY week_start)                       AS cy_revenue_running_total,
       cy_units,
       cy_customers
FROM monthly
ORDER BY week_start;

-- 5.3 Revenue per customer and units per customer (spend vs footfall)
SELECT
    ROUND(SUM(ly_sales_value) / SUM(ly_customers), 2)            AS ly_revenue_per_customer,
    ROUND(SUM(cy_sales_value) / SUM(cy_customers), 2)            AS cy_revenue_per_customer,
    ROUND(SUM(ly_units)::NUMERIC / SUM(ly_customers), 3)         AS ly_units_per_customer,
    ROUND(SUM(cy_units)::NUMERIC / SUM(cy_customers), 3)         AS cy_units_per_customer,
    ROUND(SUM(cy_visits)::NUMERIC / SUM(cy_customers), 3)        AS cy_visits_per_customer
FROM analytics.fact_sales;

-- 5.4 Growing vs declining records
SELECT CASE WHEN sales_gap >= 0 THEN 'Growing' ELSE 'Declining' END AS record_trend,
       COUNT(*)                                                    AS records,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_records,
       SUM(sales_gap)                                              AS total_gap
FROM analytics.fact_sales
GROUP BY 1;
