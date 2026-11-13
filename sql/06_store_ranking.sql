-- =====================================================================
-- STEP 06 - Rank the BEST and WORST STORES
-- Ranked by revenue and by YoY growth
-- =====================================================================

-- 6.1 Store league table
WITH store_perf AS (
    SELECT s.store_id, s.store_name,
           SUM(f.ly_sales_value) AS ly_revenue,
           SUM(f.cy_sales_value) AS cy_revenue,
           SUM(f.sales_gap)      AS revenue_gap,
           SUM(f.cy_units)       AS cy_units,
           SUM(f.cy_customers)   AS cy_customers
    FROM analytics.fact_sales f
    JOIN analytics.dim_store s USING (store_id)
    GROUP BY s.store_id, s.store_name
)
SELECT store_name,
       cy_revenue,
       ly_revenue,
       revenue_gap,
       ROUND(100.0 * (cy_revenue / ly_revenue - 1), 2)            AS yoy_pct,
       ROUND(100.0 * cy_revenue / SUM(cy_revenue) OVER (), 2)     AS share_of_revenue_pct,
       RANK() OVER (ORDER BY cy_revenue DESC)                     AS rank_by_revenue,
       RANK() OVER (ORDER BY cy_revenue / ly_revenue DESC)        AS rank_by_growth,
       ROUND(cy_revenue / cy_customers, 2)                        AS revenue_per_customer
FROM store_perf
ORDER BY rank_by_growth;

-- 6.2 Top 3 and bottom 3 stores by YoY growth, labelled
WITH ranked AS (
    SELECT s.store_name,
           SUM(f.cy_sales_value) AS cy_revenue,
           SUM(f.sales_gap)      AS revenue_gap,
           ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 2) AS yoy_pct,
           ROW_NUMBER() OVER (ORDER BY SUM(f.cy_sales_value) / SUM(f.ly_sales_value) DESC) AS best_rank,
           ROW_NUMBER() OVER (ORDER BY SUM(f.cy_sales_value) / SUM(f.ly_sales_value) ASC)  AS worst_rank
    FROM analytics.fact_sales f
    JOIN analytics.dim_store s USING (store_id)
    GROUP BY s.store_name
)
SELECT CASE WHEN best_rank <= 3 THEN 'Top ' || best_rank ELSE 'Bottom ' || worst_rank END AS position,
       store_name, cy_revenue, revenue_gap, yoy_pct
FROM ranked
WHERE best_rank <= 3 OR worst_rank <= 3
ORDER BY yoy_pct DESC;

-- 6.3 Store x product group: which product drags each store down most?
WITH sp AS (
    SELECT s.store_name, p.product_group, SUM(f.sales_gap) AS gap
    FROM analytics.fact_sales f
    JOIN analytics.dim_store   s USING (store_id)
    JOIN analytics.dim_product p USING (tpn)
    GROUP BY s.store_name, p.product_group
)
SELECT store_name, product_group AS biggest_drag_product, gap AS revenue_gap
FROM (
    SELECT sp.*, ROW_NUMBER() OVER (PARTITION BY store_name ORDER BY gap ASC) AS rn
    FROM sp
) x
WHERE rn = 1
ORDER BY revenue_gap;

-- 6.4 Store performance by month (pivot with FILTER) - YoY % per month
SELECT s.store_name,
       ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE d.month_num = 1) / SUM(ly_sales_value) FILTER (WHERE d.month_num = 1) - 1), 1) AS jan_yoy,
       ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE d.month_num = 2) / SUM(ly_sales_value) FILTER (WHERE d.month_num = 2) - 1), 1) AS feb_yoy,
       ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE d.month_num = 3) / SUM(ly_sales_value) FILTER (WHERE d.month_num = 3) - 1), 1) AS mar_yoy,
       ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE d.month_num = 4) / SUM(ly_sales_value) FILTER (WHERE d.month_num = 4) - 1), 1) AS apr_yoy,
       ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE d.month_num = 5) / SUM(ly_sales_value) FILTER (WHERE d.month_num = 5) - 1), 1) AS may_yoy,
       ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE d.month_num = 6) / SUM(ly_sales_value) FILTER (WHERE d.month_num = 6) - 1), 1) AS jun_yoy
FROM analytics.fact_sales f
JOIN analytics.dim_store s USING (store_id)
JOIN analytics.dim_date  d USING (date_key)
GROUP BY s.store_name
ORDER BY s.store_name;
