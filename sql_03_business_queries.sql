-- =====================================================================
-- 03_business_queries.sql
-- NorthBay Retail — Monthly Commercial Reporting Pack
-- Target: PostgreSQL 18, database olist_ecommerce, schema olist_dw
--
-- Purpose:
--   1. Answer the business questions in 01_requirements_note.md directly
--      in SQL, independent of Power BI.
--   2. Reconcile the Power BI measures. Each query follows the business
--      rules in 02_kpi_definitions_v2.1.md, so SQL and DAX should agree.
--      Figures marked "Expected" were observed in the Power BI report
--      for the same period.
--
-- Conventions (match the KPI definition document):
--   - Revenue = item price excluding freight, delivered orders only
--   - Order date = purchase date
--   - Customer key = customer_unique_id (customer_id is order-level
--     in the source and must never be used to count customers)
--   - Seller-level delivery and review figures use the orders that
--     contain the seller's items (the SQL equivalent of TREATAS)
--
-- Reporting period:
--   Most queries take their period from a `prm` CTE at the top of the
--   query. Default: 1 Jan 2017 – 31 Jul 2018, the period shown in the
--   report screenshots. Edit both dates to change it.
--
-- Run order: sql_01_staging.sql → sql_02_dimensions_and_facts_postgres.sql
--            → this script (read-only; creates nothing)
-- =====================================================================


-- =====================================================================
-- 0. RECONCILIATION — headline figures
-- =====================================================================

-- 0.1 Full history
-- Expected: revenue 13,221,498.11 | units 110,197 | orders 96,478
--           | AOV 137.04 | active customers 93,358
SELECT
    ROUND(SUM(oi.price)::numeric, 2)                                  AS total_revenue,
    COUNT(*)                                                          AS units_sold,
    COUNT(DISTINCT oi.order_id)                                       AS total_orders,
    ROUND((SUM(oi.price) / COUNT(DISTINCT oi.order_id))::numeric, 2)  AS average_order_value,
    COUNT(DISTINCT oi.customer_unique_id)                             AS active_customers
FROM olist_dw."Fact_OrderItems" oi
INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
WHERE fo.order_status = 'delivered';

-- 0.2 Reporting period
-- Expected (Jan 2017 – Jul 2018): revenue 12,342,450.49 | units 102,738
--           | orders 89,860 | AOV 137.35 | active customers 86,960
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
)
SELECT
    ROUND(SUM(oi.price)::numeric, 2)                                  AS total_revenue,
    COUNT(*)                                                          AS units_sold,
    COUNT(DISTINCT oi.order_id)                                       AS total_orders,
    ROUND((SUM(oi.price) / COUNT(DISTINCT oi.order_id))::numeric, 2)  AS average_order_value,
    COUNT(DISTINCT oi.customer_unique_id)                             AS active_customers
FROM olist_dw."Fact_OrderItems" oi
INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
CROSS JOIN prm
WHERE fo.order_status = 'delivered'
  AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date;


-- =====================================================================
-- 1. REVENUE AND COMMERCIAL PERFORMANCE
-- =====================================================================

-- 1.1 Monthly revenue trend with month-on-month change
-- MoM is calculated over full history first, then filtered to the
-- period, so the first month of the period is compared with the month
-- before it rather than left blank. The final month of the dataset is
-- partial and should not be read as a real decline.
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
monthly AS (
    SELECT
        d.year_month,
        MIN(d.date)                  AS month_start,
        SUM(oi.price)                AS revenue,
        COUNT(DISTINCT oi.order_id)  AS orders
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    INNER JOIN olist_dw."Dim_Date" d     ON d.date_key = fo.purchase_date_key
    WHERE fo.order_status = 'delivered'
    GROUP BY d.year_month
),
with_prior AS (
    SELECT
        year_month,
        month_start,
        revenue,
        orders,
        LAG(revenue) OVER (ORDER BY year_month) AS prior_month_revenue
    FROM monthly
)
SELECT
    w.year_month,
    ROUND(w.revenue::numeric, 2)                         AS revenue,
    w.orders,
    ROUND((w.revenue / w.orders)::numeric, 2)            AS average_order_value,
    ROUND((100.0 * (w.revenue - w.prior_month_revenue)
           / NULLIF(w.prior_month_revenue, 0))::numeric, 1) AS revenue_mom_pct
FROM with_prior w
CROSS JOIN prm
WHERE w.month_start BETWEEN prm.start_date AND prm.end_date
ORDER BY w.year_month;

-- 1.2 Category mix — revenue, volume, AOV, share and freight ratio
-- Expected (period): health_beauty 1,110,166.49 | 8,587 units
--           | 7,845 orders | AOV 141.51 | 9.0% share
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
cat AS (
    SELECT
        pr.category,
        SUM(oi.price)                AS revenue,
        COUNT(*)                     AS units_sold,
        COUNT(DISTINCT oi.order_id)  AS orders,
        SUM(oi.freight_value)        AS freight
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo  ON fo.order_id = oi.order_id
    INNER JOIN olist_dw."Dim_Product" pr  ON pr.product_id = oi.product_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
    GROUP BY pr.category
)
SELECT
    category,
    ROUND(revenue::numeric, 2)                                   AS revenue,
    units_sold,
    orders,
    ROUND((revenue / orders)::numeric, 2)                        AS average_order_value,
    ROUND((100.0 * revenue / SUM(revenue) OVER ())::numeric, 1)  AS revenue_share_pct,
    ROUND((100.0 * freight / NULLIF(revenue, 0))::numeric, 1)    AS freight_cost_ratio_pct
FROM cat
ORDER BY revenue DESC;

-- 1.3 Executive Summary category table — reproduces the Power BI
--     measure Revenue MoM % Change (Material) as implemented
--
-- DATEADD(..., -1, MONTH) shifts the whole selected date range back by
-- one month. For a Jan 2017 – Jul 2018 selection, the comparison window
-- is therefore Dec 2016 – Jun 2018. This query reproduces that exactly
-- so the figures reconcile. MoM % is suppressed (NULL) for categories
-- below 50,000 BRL of revenue in the period; the row is kept, so the
-- total still reconciles to the Total Revenue KPI.
--
-- Expected (period): fixed_telephony 51,886.16 | 21.9%
--                    Total 12,342,450.49 | 7.6%
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
cur AS (
    SELECT pr.category, SUM(oi.price) AS revenue
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo  ON fo.order_id = oi.order_id
    INNER JOIN olist_dw."Dim_Product" pr  ON pr.product_id = oi.product_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
    GROUP BY pr.category
),
prev AS (
    SELECT pr.category, SUM(oi.price) AS revenue
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo  ON fo.order_id = oi.order_id
    INNER JOIN olist_dw."Dim_Product" pr  ON pr.product_id = oi.product_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN (prm.start_date - INTERVAL '1 month')::date
                               AND (prm.end_date   - INTERVAL '1 month')::date
    GROUP BY pr.category
),
category_rows AS (
    SELECT
        c.category,
        c.revenue,
        CASE
            WHEN c.revenue >= 50000 AND p.revenue IS NOT NULL
            THEN 100.0 * (c.revenue - p.revenue) / NULLIF(p.revenue, 0)
        END                                              AS mom_pct_material,
        100.0 * c.revenue / SUM(c.revenue) OVER ()       AS share_pct
    FROM cur c
    LEFT JOIN prev p ON p.category = c.category
)
SELECT
    category,
    ROUND(revenue::numeric, 2)           AS revenue,
    ROUND(mom_pct_material::numeric, 1)  AS revenue_mom_pct_material,
    ROUND(share_pct::numeric, 1)         AS revenue_share_pct
FROM category_rows
ORDER BY mom_pct_material DESC NULLS LAST, revenue DESC;

-- Total row for 1.3
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
totals AS (
    SELECT
        SUM(oi.price) FILTER (
            WHERE fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
        ) AS cur_revenue,
        SUM(oi.price) FILTER (
            WHERE fo.purchase_date::date BETWEEN (prm.start_date - INTERVAL '1 month')::date
                                       AND (prm.end_date   - INTERVAL '1 month')::date
        ) AS prev_revenue
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
)
SELECT
    'Total'                                                        AS category,
    ROUND(cur_revenue::numeric, 2)                                 AS revenue,
    ROUND((100.0 * (cur_revenue - prev_revenue)
           / NULLIF(prev_revenue, 0))::numeric, 1)                 AS revenue_mom_pct_material,
    100.0                                                          AS revenue_share_pct
FROM totals;


-- =====================================================================
-- 2. CUSTOMER BEHAVIOUR  (all counts on customer_unique_id)
-- =====================================================================

-- 2.1 Lifetime repeat purchase rate (full history)
-- Repeat customer = more than one delivered order.
-- Expected (full history, 01/01/2016 – 31/12/2018 in Power BI):
--           93,358 active customers | 2,801 repeat customers | 3.00%
-- Validated result — the source of the lifetime figure in the findings
-- memo and README.
WITH customer_orders AS (
    SELECT
        oi.customer_unique_id,
        COUNT(DISTINCT oi.order_id) AS delivered_orders
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    WHERE fo.order_status = 'delivered'
    GROUP BY oi.customer_unique_id
)
SELECT
    COUNT(*)                                             AS active_customers,
    COUNT(*) FILTER (WHERE delivered_orders > 1)         AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders > 1)
          / COUNT(*), 2)                                 AS repeat_purchase_rate_pct
FROM customer_orders;

-- 2.2 Repeat purchase rate within the reporting period
-- Counts only orders placed inside the period, so it is window-sensitive.
-- Expected (period): 3.0%
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
customer_orders AS (
    SELECT
        oi.customer_unique_id,
        COUNT(DISTINCT oi.order_id) AS delivered_orders
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
    GROUP BY oi.customer_unique_id
)
SELECT
    COUNT(*)                                             AS active_customers,
    COUNT(*) FILTER (WHERE delivered_orders > 1)         AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_orders > 1)
          / COUNT(*), 2)                                 AS repeat_purchase_rate_pct
FROM customer_orders;

-- 2.3 New vs returning customers for the whole period
-- New = active in the period AND first delivered order inside the period.
-- Returning = Active − New (matches the DAX definitions).
-- Expected (period): active 86,960 | returning 10
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
active AS (
    SELECT DISTINCT oi.customer_unique_id
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
),
classified AS (
    SELECT
        a.customer_unique_id,
        (dc.first_order_date BETWEEN prm.start_date AND prm.end_date) AS is_new
    FROM active a
    INNER JOIN olist_dw."Dim_Customer" dc ON dc.customer_unique_id = a.customer_unique_id
    CROSS JOIN prm
)
SELECT
    COUNT(*)                                        AS active_customers,
    COUNT(*) FILTER (WHERE is_new)                  AS new_customers,
    COUNT(*) - COUNT(*) FILTER (WHERE is_new)       AS returning_customers
FROM classified;

-- 2.4 New vs returning customers by month
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
monthly_active AS (
    SELECT DISTINCT
        d.year_month,
        oi.customer_unique_id
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    INNER JOIN olist_dw."Dim_Date" d     ON d.date_key = fo.purchase_date_key
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
)
SELECT
    ma.year_month,
    COUNT(*)                                                         AS active_customers,
    COUNT(*) FILTER (
        WHERE TO_CHAR(dc.first_order_date, 'YYYY-MM') = ma.year_month
    )                                                                AS new_customers,
    COUNT(*) - COUNT(*) FILTER (
        WHERE TO_CHAR(dc.first_order_date, 'YYYY-MM') = ma.year_month
    )                                                                AS returning_customers
FROM monthly_active ma
INNER JOIN olist_dw."Dim_Customer" dc ON dc.customer_unique_id = ma.customer_unique_id
GROUP BY ma.year_month
ORDER BY ma.year_month;

-- 2.5 Revenue by customer state (most recent location)
-- Expected (period): SP 4,669,948.00 | 36,001 customers
--           | revenue per customer 129.72 | AOV 125.37
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
)
SELECT
    dc.most_recent_customer_state                                          AS customer_state,
    ROUND(SUM(oi.price)::numeric, 2)                                       AS revenue,
    COUNT(DISTINCT oi.customer_unique_id)                                  AS active_customers,
    ROUND((SUM(oi.price) / COUNT(DISTINCT oi.customer_unique_id))::numeric, 2) AS revenue_per_customer,
    ROUND((SUM(oi.price) / COUNT(DISTINCT oi.order_id))::numeric, 2)       AS average_order_value
FROM olist_dw."Fact_OrderItems" oi
INNER JOIN olist_dw."Fact_Orders" fo  ON fo.order_id = oi.order_id
INNER JOIN olist_dw."Dim_Customer" dc ON dc.customer_unique_id = fo.customer_unique_id
CROSS JOIN prm
WHERE fo.order_status = 'delivered'
  AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
GROUP BY dc.most_recent_customer_state
ORDER BY revenue DESC;


-- =====================================================================
-- 3. SELLER PERFORMANCE
-- =====================================================================

-- 3.1 Active sellers and top-10 revenue concentration
-- Expected (period): top 10 seller revenue share 13.6%
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
seller_revenue AS (
    SELECT
        oi.seller_id,
        SUM(oi.price) AS revenue
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
    GROUP BY oi.seller_id
),
ranked AS (
    SELECT revenue, ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rn
    FROM seller_revenue
)
SELECT
    COUNT(*)                                                   AS total_sellers,
    ROUND((100.0 * SUM(revenue) FILTER (WHERE rn <= 10)
           / SUM(revenue))::numeric, 1)                        AS top_10_seller_revenue_share_pct
FROM ranked;

-- 3.2 Top 15 sellers by revenue
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
)
SELECT
    s.seller_id,
    s.seller_state,
    ROUND(SUM(oi.price)::numeric, 2)  AS revenue,
    COUNT(DISTINCT oi.order_id)       AS orders
FROM olist_dw."Fact_OrderItems" oi
INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
INNER JOIN olist_dw."Dim_Seller" s   ON s.seller_id = oi.seller_id
CROSS JOIN prm
WHERE fo.order_status = 'delivered'
  AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
GROUP BY s.seller_id, s.seller_state
ORDER BY revenue DESC
LIMIT 15;

-- 3.3 Worst-performing sellers — 20+ reviews only
-- Reproduces the seller-aware measures: reviews and delivery outcomes
-- are taken from the orders that contain each seller's items. Review
-- count and score cover all order statuses (as in the DAX); late rate
-- covers delivered orders only.
-- Expected (period): 1ca7077d890b907f89be8c954a02686a | SP | 12,474.64
--           | 114 reviews | 2.33 | 22.2% late
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
seller_orders AS (
    SELECT DISTINCT oi.seller_id, oi.order_id
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    CROSS JOIN prm
    WHERE fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
),
seller_reviews AS (
    SELECT
        so.seller_id,
        COUNT(DISTINCT r.review_id)  AS review_count,
        AVG(r.review_score)          AS avg_review_score
    FROM seller_orders so
    INNER JOIN olist_dw."Fact_Reviews" r ON r.order_id = so.order_id
    GROUP BY so.seller_id
),
seller_delivery AS (
    SELECT
        so.seller_id,
        COUNT(DISTINCT fo.order_id) FILTER (WHERE fo.is_late::int = 1) AS late_orders,
        COUNT(DISTINCT fo.order_id)                                   AS delivered_orders
    FROM seller_orders so
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = so.order_id
    WHERE fo.order_status = 'delivered'
    GROUP BY so.seller_id
),
seller_revenue AS (
    SELECT oi.seller_id, SUM(oi.price) AS revenue
    FROM olist_dw."Fact_OrderItems" oi
    INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
    GROUP BY oi.seller_id
)
SELECT
    s.seller_id,
    s.seller_state,
    ROUND(COALESCE(sr.revenue, 0)::numeric, 2)                        AS revenue,
    rv.review_count,
    ROUND(rv.avg_review_score::numeric, 2)                            AS avg_review_score,
    ROUND((100.0 * sd.late_orders
           / NULLIF(sd.delivered_orders, 0))::numeric, 1)             AS late_delivery_rate_pct
FROM seller_reviews rv
INNER JOIN olist_dw."Dim_Seller" s   ON s.seller_id = rv.seller_id
LEFT JOIN seller_delivery sd         ON sd.seller_id = rv.seller_id
LEFT JOIN seller_revenue sr          ON sr.seller_id = rv.seller_id
WHERE rv.review_count >= 20
ORDER BY rv.avg_review_score ASC
LIMIT 20;

-- 3.4 Cancellation rate — marketplace-wide vs seller-scoped
-- The marketplace rate uses every order. The seller-scoped rate uses
-- only orders that have at least one order-item row, because an order
-- with no items cannot be attributed to a seller. The two figures
-- therefore differ, and only the seller-scoped one belongs on the
-- Seller Performance page.
-- Expected (period): seller-scoped 0.5%
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
period_orders AS (
    SELECT fo.order_id, fo.order_status
    FROM olist_dw."Fact_Orders" fo
    CROSS JOIN prm
    WHERE fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
),
orders_with_items AS (
    SELECT DISTINCT po.order_id, po.order_status
    FROM period_orders po
    INNER JOIN olist_dw."Fact_OrderItems" oi ON oi.order_id = po.order_id
)
SELECT
    ROUND(100.0 * (SELECT COUNT(*) FROM period_orders
                   WHERE order_status IN ('canceled', 'unavailable'))
          / NULLIF((SELECT COUNT(*) FROM period_orders), 0), 1)       AS marketplace_cancellation_rate_pct,
    ROUND(100.0 * (SELECT COUNT(*) FROM orders_with_items
                   WHERE order_status IN ('canceled', 'unavailable'))
          / NULLIF((SELECT COUNT(*) FROM orders_with_items), 0), 1)   AS seller_scoped_cancellation_rate_pct;


-- =====================================================================
-- 4. DELIVERY AND SATISFACTION  (order-level)
-- =====================================================================

-- 4.1 Headline delivery and review figures
-- Late = delivered after the estimated delivery date.
-- Expected (period): 12.8 days | 92.0% on time | 8.0% late | 4.15 score
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
delivered AS (
    SELECT fo.*
    FROM olist_dw."Fact_Orders" fo
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
)
SELECT
    ROUND(AVG(delivery_days)::numeric, 1)                              AS average_delivery_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late::int = 0) / COUNT(*), 1) AS on_time_delivery_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late::int = 1) / COUNT(*), 1) AS late_delivery_rate_pct,
    (SELECT ROUND(AVG(r.review_score)::numeric, 2)
     FROM olist_dw."Fact_Reviews" r
     INNER JOIN delivered d ON d.order_id = r.order_id)                AS average_review_score
FROM delivered;

-- 4.2 Review coverage (full history)
-- Validated result: 95,832 reviewed of 96,478 delivered orders = 99.33%
SELECT
    COUNT(DISTINCT r.order_id)                                         AS reviewed,
    COUNT(DISTINCT o.order_id)                                         AS delivered,
    ROUND(100.0 * COUNT(DISTINCT r.order_id)
          / COUNT(DISTINCT o.order_id), 2)                             AS coverage_pct
FROM olist_dw."Fact_Orders" o
LEFT JOIN olist_dw."Fact_Reviews" r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- 4.3 Review score by delivery outcome — the late delivery review gap
-- An observed association, not proof that late delivery causes lower
-- scores.
-- Expected (period): on time 4.08 | late 2.48 | gap 1.60
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
),
scores AS (
    SELECT
        AVG(r.review_score) FILTER (WHERE fo.is_late::int = 0) AS on_time_score,
        AVG(r.review_score) FILTER (WHERE fo.is_late::int = 1) AS late_score,
        COUNT(r.review_id)  FILTER (WHERE fo.is_late::int = 0) AS on_time_reviews,
        COUNT(r.review_id)  FILTER (WHERE fo.is_late::int = 1) AS late_reviews
    FROM olist_dw."Fact_Orders" fo
    INNER JOIN olist_dw."Fact_Reviews" r ON r.order_id = fo.order_id
    CROSS JOIN prm
    WHERE fo.order_status = 'delivered'
      AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
)
SELECT
    on_time_reviews,
    ROUND(on_time_score::numeric, 2)                  AS avg_review_score_on_time,
    late_reviews,
    ROUND(late_score::numeric, 2)                     AS avg_review_score_late,
    ROUND((on_time_score - late_score)::numeric, 2)   AS late_delivery_review_gap
FROM scores;

-- 4.4 Late delivery rate by customer state
-- Expected (period): AL, MA and PI have the highest late rates
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
)
SELECT
    dc.most_recent_customer_state                                        AS customer_state,
    COUNT(*)                                                             AS delivered_orders,
    ROUND(AVG(fo.delivery_days)::numeric, 1)                             AS average_delivery_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE fo.is_late::int = 1)
          / COUNT(*), 1)                                                 AS late_delivery_rate_pct
FROM olist_dw."Fact_Orders" fo
INNER JOIN olist_dw."Dim_Customer" dc ON dc.customer_unique_id = fo.customer_unique_id
CROSS JOIN prm
WHERE fo.order_status = 'delivered'
  AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
GROUP BY dc.most_recent_customer_state
ORDER BY late_delivery_rate_pct DESC;

-- 4.5 Monthly delivery trend
WITH prm AS (
    SELECT DATE '2017-01-01' AS start_date, DATE '2018-07-31' AS end_date
)
SELECT
    d.year_month,
    COUNT(*)                                                             AS delivered_orders,
    ROUND(AVG(fo.delivery_days)::numeric, 1)                             AS average_delivery_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE fo.is_late::int = 0)
          / COUNT(*), 1)                                                 AS on_time_delivery_rate_pct
FROM olist_dw."Fact_Orders" fo
INNER JOIN olist_dw."Dim_Date" d ON d.date_key = fo.purchase_date_key
CROSS JOIN prm
WHERE fo.order_status = 'delivered'
  AND fo.purchase_date::date BETWEEN prm.start_date AND prm.end_date
GROUP BY d.year_month
ORDER BY d.year_month;
