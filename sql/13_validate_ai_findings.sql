-- =====================================================================
-- STEP 13 - Fact-check an AI-generated analysis against the database
--
-- Workflow: give the same dataset to a GenAI tool, list each claim it
-- makes, then verify every claim with SQL before relying on it.
-- Enter the AI tool's figures in the ai_claimed / ai_answer values.
-- =====================================================================

-- 13.1 Numeric claims: compare AI-stated figures with SQL-computed figures
WITH ai_claims (claim, ai_claimed) AS (
    VALUES
        ('Total current revenue (£)',             2480524.12),
        ('Revenue YoY change %',                  -8.5),
        ('Weakest product group YoY %',           -36.3),
        ('Store channel YoY %',                   -16.3),
        ('Online channels YoY %',                 6.0)
),
sql_facts (claim, sql_value) AS (
    SELECT 'Total current revenue (£)', SUM(cy_sales_value) FROM analytics.fact_sales
    UNION ALL
    SELECT 'Revenue YoY change %', ROUND(100.0 * (SUM(cy_sales_value) / SUM(ly_sales_value) - 1), 1)
    FROM analytics.fact_sales
    UNION ALL
    SELECT 'Weakest product group YoY %', revenue_yoy_pct FROM analytics.vw_weakest_product
    UNION ALL
    SELECT 'Store channel YoY %', ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1)
    FROM analytics.fact_sales f JOIN analytics.dim_channel c USING (channel_id) WHERE NOT c.is_online
    UNION ALL
    SELECT 'Online channels YoY %', ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1)
    FROM analytics.fact_sales f JOIN analytics.dim_channel c USING (channel_id) WHERE c.is_online
)
SELECT a.claim, a.ai_claimed, s.sql_value,
       ROUND(s.sql_value - a.ai_claimed, 2) AS difference,
       CASE WHEN ABS(s.sql_value - a.ai_claimed) <= GREATEST(0.5, ABS(s.sql_value) * 0.005)
            THEN 'AGREES' ELSE 'DIFFERS - investigate' END AS verdict
FROM ai_claims a
JOIN sql_facts s USING (claim);

-- 13.2 Ranking claims: does the AI's "best / worst" list match SQL?
WITH ai_ranking (dimension, position, ai_answer) AS (
    VALUES
        ('Store',         'Best',  'Norwich Riverside'),
        ('Store',         'Worst', 'Peterborough Retail Park'),
        ('Product group', 'Best',  'SEASONINGS'),
        ('Product group', 'Worst', 'EVERYDAY 2 LITRE TUBS'),
        ('Channel',       'Best',  'Click & Collect'),
        ('Channel',       'Worst', 'Store')
),
growth AS (
    SELECT 'Store' AS dimension, s.store_name AS member, SUM(f.cy_sales_value) / SUM(f.ly_sales_value) AS g
    FROM analytics.fact_sales f JOIN analytics.dim_store s USING (store_id) GROUP BY s.store_name
    UNION ALL
    SELECT 'Product group', p.product_group, SUM(f.cy_sales_value) / SUM(f.ly_sales_value)
    FROM analytics.fact_sales f JOIN analytics.dim_product p USING (tpn) GROUP BY p.product_group
    UNION ALL
    SELECT 'Channel', c.channel_name, SUM(f.cy_sales_value) / SUM(f.ly_sales_value)
    FROM analytics.fact_sales f JOIN analytics.dim_channel c USING (channel_id) GROUP BY c.channel_name
),
sql_ranking AS (
    SELECT DISTINCT dimension,
           FIRST_VALUE(member) OVER (PARTITION BY dimension ORDER BY g DESC) AS best,
           FIRST_VALUE(member) OVER (PARTITION BY dimension ORDER BY g ASC)  AS worst
    FROM growth
)
SELECT a.dimension, a.position, a.ai_answer,
       CASE a.position WHEN 'Best' THEN r.best ELSE r.worst END AS sql_answer,
       CASE WHEN a.ai_answer = CASE a.position WHEN 'Best' THEN r.best ELSE r.worst END
            THEN 'AGREES' ELSE 'DIFFERS' END AS verdict
FROM ai_ranking a
JOIN sql_ranking r USING (dimension)
ORDER BY a.dimension, a.position;

-- 13.3 Additional checks
--      (a) the decline is entirely in-store; online is growing
--      (b) price premium vs competitor tracks the decline almost perfectly
--      (c) 5 rows fail a logic check (customers > visits)
SELECT 'In-store vs online split' AS check_name,
       'In-store ' || ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE NOT c.is_online)
                                    / SUM(ly_sales_value) FILTER (WHERE NOT c.is_online) - 1), 1)
       || '% | Online +' || ROUND(100.0 * (SUM(cy_sales_value) FILTER (WHERE c.is_online)
                                          / SUM(ly_sales_value) FILTER (WHERE c.is_online) - 1), 1) || '%' AS finding
FROM analytics.fact_sales f JOIN analytics.dim_channel c USING (channel_id)
UNION ALL
SELECT 'Premium vs competitor <-> revenue YoY correlation',
       ROUND(CORR(premium, yoy)::NUMERIC, 3)::TEXT
FROM (SELECT SUM(cy_sales_value) / SUM(competitor_avg_price * cy_units) - 1 AS premium,
             SUM(cy_sales_value) / SUM(ly_sales_value) - 1                  AS yoy
      FROM analytics.fact_sales GROUP BY tpn) g
UNION ALL
SELECT 'Rows with customers > visits (data issue)',
       COUNT(*)::TEXT
FROM analytics.fact_sales WHERE dq_customers_gt_visits;
