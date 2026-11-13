-- =====================================================================
-- STEP 12 - Customer complaints analysis (dataset 2)
-- =====================================================================

-- 12.1 Complaint overview
SELECT COUNT(*)                                                    AS complaints,
       MIN(complaint_date)                                         AS first_date,
       MAX(complaint_date)                                         AS last_date,
       ROUND(AVG(severity), 2)                                     AS avg_severity,
       ROUND(100.0 * AVG(is_repeat_complaint::INT), 1)             AS repeat_complaint_pct,
       ROUND(100.0 * AVG((severity >= 4)::INT), 1)                 AS high_severity_pct
FROM analytics.fact_complaints;

-- 12.2 Complaint themes ranked
SELECT complaint_theme,
       COUNT(*)                                                AS complaints,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct_of_total,
       ROUND(AVG(severity), 2)                                 AS avg_severity,
       ROUND(100.0 * AVG(is_repeat_complaint::INT), 1)         AS repeat_pct,
       RANK() OVER (ORDER BY COUNT(*) DESC)                    AS rank_by_volume
FROM analytics.fact_complaints
GROUP BY complaint_theme
ORDER BY complaints DESC;

-- 12.3 Complaints by month (DATE_TRUNC on the cleaned DATE column)
SELECT TO_CHAR(DATE_TRUNC('month', complaint_date), 'Mon-YYYY') AS month,
       COUNT(*)                                                 AS complaints,
       ROUND(AVG(severity), 2)                                  AS avg_severity
FROM analytics.fact_complaints
GROUP BY DATE_TRUNC('month', complaint_date)
ORDER BY DATE_TRUNC('month', complaint_date);

-- 12.4 Complaints by product group joined to sales performance
WITH sales AS (
    SELECT p.product_group,
           ROUND(100.0 * (SUM(f.cy_sales_value) / SUM(f.ly_sales_value) - 1), 1) AS revenue_yoy_pct
    FROM analytics.fact_sales f
    JOIN analytics.dim_product p USING (tpn)
    GROUP BY p.product_group
),
comp AS (
    SELECT product_group,
           COUNT(*)                AS complaints,
           ROUND(AVG(severity), 2) AS avg_severity,
           COUNT(*) FILTER (WHERE customer_sentiment = 'Very Negative') AS very_negative
    FROM analytics.fact_complaints
    GROUP BY product_group
)
SELECT s.product_group, s.revenue_yoy_pct,
       COALESCE(c.complaints, 0) AS complaints,
       c.avg_severity, c.very_negative
FROM sales s
LEFT JOIN comp c USING (product_group)
ORDER BY s.revenue_yoy_pct;

-- 12.5 Channel x sentiment cross-tab
SELECT complaint_channel,
       COUNT(*) FILTER (WHERE customer_sentiment = 'Very Negative') AS very_negative,
       COUNT(*) FILTER (WHERE customer_sentiment = 'Negative')      AS negative,
       COUNT(*) FILTER (WHERE customer_sentiment = 'Frustrated')    AS frustrated,
       COUNT(*) FILTER (WHERE customer_sentiment NOT IN ('Very Negative','Negative','Frustrated')) AS other,
       COUNT(*)                                                     AS total
FROM analytics.fact_complaints
GROUP BY complaint_channel
ORDER BY total DESC;

-- 12.6 Most common customer expectations
SELECT customer_expectation, COUNT(*) AS mentions
FROM analytics.fact_complaints
GROUP BY customer_expectation
ORDER BY mentions DESC
LIMIT 10;

-- 12.7 Complaints for the weakest product line
SELECT c.complaint_theme, c.customer_segment, COUNT(*) AS complaints, ROUND(AVG(c.severity), 2) AS avg_severity
FROM analytics.fact_complaints c
JOIN analytics.vw_weakest_product w USING (product_group)
GROUP BY c.complaint_theme, c.customer_segment
ORDER BY complaints DESC
LIMIT 10;

-- 12.8 Linked business problems
SELECT linked_business_problem, COUNT(*) AS complaints,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM analytics.fact_complaints
GROUP BY linked_business_problem
ORDER BY complaints DESC;
