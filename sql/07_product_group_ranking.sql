-- =====================================================================
-- STEP 07 - Rank the BEST and WORST PRODUCT GROUPS
-- Includes each group's contribution to the total revenue decline
-- =====================================================================

-- 7.1 Product group league table
WITH pg AS (
    SELECT p.product_group, p.product_name,
           SUM(f.ly_sales_value) AS ly_revenue,
           SUM(f.cy_sales_value) AS cy_revenue,
           SUM(f.sales_gap)      AS revenue_gap,
           SUM(f.ly_units)       AS ly_units,
           SUM(f.cy_units)       AS cy_units
    FROM analytics.fact_sales f
    JOIN analytics.dim_product p USING (tpn)
    GROUP BY p.product_group, p.product_name
)
SELECT product_group,
       product_name,
       ly_revenue,
       cy_revenue,
       revenue_gap,
       ROUND(100.0 * (cy_revenue / ly_revenue - 1), 2)         AS revenue_yoy_pct,
       ROUND(100.0 * (cy_units::NUMERIC / ly_units - 1), 2)    AS units_yoy_pct,
       ROUND(100.0 * cy_revenue / SUM(cy_revenue) OVER (), 2)  AS share_of_revenue_pct,
       RANK() OVER (ORDER BY cy_revenue / ly_revenue DESC)     AS growth_rank,
       CASE
           WHEN cy_revenue / ly_revenue >= 1.05 THEN 'Strong growth'
           WHEN cy_revenue / ly_revenue >= 1.00 THEN 'Flat / slight growth'
           WHEN cy_revenue / ly_revenue >= 0.90 THEN 'Moderate decline'
           ELSE 'Severe decline'
       END                                                      AS performance_band
FROM pg
ORDER BY growth_rank;

-- 7.2 Each product group's contribution to the decline
WITH pg AS (
    SELECT p.product_group, SUM(f.sales_gap) AS gap
    FROM analytics.fact_sales f
    JOIN analytics.dim_product p USING (tpn)
    GROUP BY p.product_group
)
SELECT product_group,
       gap,
       ROUND(100.0 * gap / SUM(gap) FILTER (WHERE gap < 0) OVER (), 1) AS pct_of_total_losses,
       SUM(gap) OVER (ORDER BY gap)                                    AS cumulative_gap,
       ROUND(100.0 * gap / SUM(gap) OVER (), 1)                        AS pct_of_net_decline
FROM pg
ORDER BY gap;

-- 7.3 Losses from declining groups vs gains from growing groups
SELECT
    SUM(sales_gap) FILTER (WHERE grp_gap < 0) AS losses_from_declining_groups,
    SUM(sales_gap) FILTER (WHERE grp_gap >= 0) AS gains_from_growing_groups,
    SUM(sales_gap)                             AS net_revenue_change
FROM (
    SELECT f.sales_gap,
           SUM(f.sales_gap) OVER (PARTITION BY f.tpn) AS grp_gap
    FROM analytics.fact_sales f
) x;

-- 7.4 Product group YoY % by month
SELECT p.product_group,
       d.month_label,
       SUM(f.cy_sales_value)                                                   AS cy_revenue,
       ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1)  AS yoy_pct
FROM analytics.fact_sales f
JOIN analytics.dim_product p USING (tpn)
JOIN analytics.dim_date    d USING (date_key)
GROUP BY p.product_group, d.week_start, d.month_label
ORDER BY p.product_group, d.week_start;
