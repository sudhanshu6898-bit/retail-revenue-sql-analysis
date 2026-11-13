-- =====================================================================
-- STEP 11 - Shopper profile analysis
-- Appeal index: 100 = average, >110 = strong appeal, <90 = weak appeal
-- =====================================================================

-- 11.1 Top 3 shopper segments each product group appeals to
SELECT product_group, segment_type, segment, appeal_index, rnk
FROM (
    SELECT a.*,
           ROW_NUMBER() OVER (PARTITION BY product_group ORDER BY appeal_index DESC) AS rnk
    FROM analytics.shopper_appeal a
) x
WHERE rnk <= 3
ORDER BY product_group, rnk;

-- 11.2 Average appeal to each segment: DECLINING vs GROWING product groups
WITH perf AS (
    SELECT p.product_group,
           CASE WHEN SUM(f.cy_sales_value) < SUM(f.ly_sales_value) THEN 'Declining' ELSE 'Growing' END AS trend
    FROM analytics.fact_sales f
    JOIN analytics.dim_product p USING (tpn)
    GROUP BY p.product_group
)
SELECT a.segment_type,
       a.segment,
       ROUND(AVG(a.appeal_index) FILTER (WHERE pf.trend = 'Declining'), 1) AS avg_appeal_declining_groups,
       ROUND(AVG(a.appeal_index) FILTER (WHERE pf.trend = 'Growing'), 1)   AS avg_appeal_growing_groups,
       ROUND(AVG(a.appeal_index) FILTER (WHERE pf.trend = 'Declining')
           - AVG(a.appeal_index) FILTER (WHERE pf.trend = 'Growing'), 1)   AS difference
FROM analytics.shopper_appeal a
JOIN perf pf USING (product_group)
GROUP BY a.segment_type, a.segment
ORDER BY difference DESC;

-- 11.3 Correlation of each segment's appeal with product revenue growth
--      (positive = products this segment likes are growing)
WITH perf AS (
    SELECT p.product_group,
           SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1 AS revenue_yoy
    FROM analytics.fact_sales f
    JOIN analytics.dim_product p USING (tpn)
    GROUP BY p.product_group
)
SELECT a.segment,
       ROUND(CORR(a.appeal_index, pf.revenue_yoy)::NUMERIC, 3) AS corr_appeal_vs_growth
FROM analytics.shopper_appeal a
JOIN perf pf USING (product_group)
GROUP BY a.segment
ORDER BY corr_appeal_vs_growth;

-- 11.4 Appeal profile of the weakest product
SELECT a.segment_type, a.segment, a.appeal_index,
       CASE WHEN a.appeal_index >= 110 THEN 'Core target'
            WHEN a.appeal_index >= 100 THEN 'Secondary'
            ELSE 'Low appeal' END AS targeting
FROM analytics.shopper_appeal a
JOIN analytics.vw_weakest_product w USING (product_group)
ORDER BY a.appeal_index DESC;

-- 11.5 Revenue trend by the lifestage / lifestyle recorded on each sales row
SELECT customer_lifestage,
       SUM(cy_sales_value)                                                 AS cy_revenue,
       ROUND(100.0 * (SUM(cy_sales_value) / SUM(ly_sales_value) - 1), 1)  AS revenue_yoy_pct
FROM analytics.fact_sales
GROUP BY customer_lifestage
ORDER BY revenue_yoy_pct;

SELECT lifestyle_segment,
       SUM(cy_sales_value)                                                 AS cy_revenue,
       ROUND(100.0 * (SUM(cy_sales_value) / SUM(ly_sales_value) - 1), 1)  AS revenue_yoy_pct
FROM analytics.fact_sales
GROUP BY lifestyle_segment
ORDER BY revenue_yoy_pct;
