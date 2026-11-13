-- =====================================================================
-- STEP 08 - Rank CHANNELS (Store, Click & Collect, Online Delivery)
-- =====================================================================

-- 8.1 Channel league table
SELECT c.channel_name,
       c.is_online,
       SUM(f.ly_sales_value)                                                   AS ly_revenue,
       SUM(f.cy_sales_value)                                                   AS cy_revenue,
       SUM(f.sales_gap)                                                        AS revenue_gap,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 2)  AS yoy_pct,
       ROUND(100.0 * SUM(f.cy_sales_value) / SUM(SUM(f.cy_sales_value)) OVER (), 2) AS share_cy_pct,
       ROUND(100.0 * SUM(f.ly_sales_value) / SUM(SUM(f.ly_sales_value)) OVER (), 2) AS share_ly_pct,
       RANK() OVER (ORDER BY SUM(f.cy_sales_value) / SUM(f.ly_sales_value) DESC) AS growth_rank
FROM analytics.fact_sales f
JOIN analytics.dim_channel c USING (channel_id)
GROUP BY c.channel_name, c.is_online
ORDER BY growth_rank;

-- 8.2 Online (Click & Collect + Delivery) vs physical store
SELECT CASE WHEN c.is_online THEN 'Online' ELSE 'In-store' END AS channel_type,
       SUM(f.cy_sales_value)                                                   AS cy_revenue,
       SUM(f.sales_gap)                                                        AS revenue_gap,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 2)  AS yoy_pct
FROM analytics.fact_sales f
JOIN analytics.dim_channel c USING (channel_id)
GROUP BY 1;

-- 8.3 Channel x product group YoY %
SELECT p.product_group,
       ROUND(100.0 * (SUM(f.cy_sales_value) FILTER (WHERE c.channel_name = 'Store')
                    / SUM(f.ly_sales_value) FILTER (WHERE c.channel_name = 'Store') - 1), 1)           AS store_yoy,
       ROUND(100.0 * (SUM(f.cy_sales_value) FILTER (WHERE c.channel_name = 'Click & Collect')
                    / SUM(f.ly_sales_value) FILTER (WHERE c.channel_name = 'Click & Collect') - 1), 1) AS click_collect_yoy,
       ROUND(100.0 * (SUM(f.cy_sales_value) FILTER (WHERE c.channel_name = 'Online Delivery')
                    / SUM(f.ly_sales_value) FILTER (WHERE c.channel_name = 'Online Delivery') - 1), 1) AS online_delivery_yoy
FROM analytics.fact_sales f
JOIN analytics.dim_channel c USING (channel_id)
JOIN analytics.dim_product p USING (tpn)
GROUP BY p.product_group
ORDER BY store_yoy;

-- 8.4 Best and worst store-channel combinations (top 5 / bottom 5)
WITH sc AS (
    SELECT s.store_name, c.channel_name,
           SUM(f.cy_sales_value) AS cy_revenue,
           ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 2) AS yoy_pct
    FROM analytics.fact_sales f
    JOIN analytics.dim_store   s USING (store_id)
    JOIN analytics.dim_channel c USING (channel_id)
    GROUP BY s.store_name, c.channel_name
)
(SELECT 'Best'  AS label, * FROM sc ORDER BY yoy_pct DESC LIMIT 5)
UNION ALL
(SELECT 'Worst' AS label, * FROM sc ORDER BY yoy_pct ASC  LIMIT 5);
