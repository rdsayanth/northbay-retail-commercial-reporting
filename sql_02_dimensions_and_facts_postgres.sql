-- =====================================================================
-- 02_dimensions_and_facts_postgres.sql
-- NorthBay Retail — Monthly Commercial Reporting Pack
-- Target: PostgreSQL 18, database olist_ecommerce
-- Purpose: Build the star schema (Dim_* and Fact_*) in schema olist_dw
-- from olist_stg. Power BI connects to olist_dw only.
--
-- IMPORTANT — customer grain:
-- Olist assigns a new customer_id per order. customer_unique_id is the
-- true person-level key and is used as the grain of Dim_Customer and
-- as the join key from Fact_Orders. customer_id is retained on
-- Fact_Orders only for traceability back to the source order record.
--
-- PREREQUISITES — this script reads from olist_stg and expects:
--   olist_stg.orders      order_id, customer_id, order_status,
--                         purchase_date, order_approved_at,
--                         delivered_customer_date, estimated_delivery_date,
--                         is_late (0/1), delivery_days (integer days)
--   olist_stg.order_items order_id, order_item_id, product_id, seller_id,
--                         price, freight_value
--   olist_stg.customers   customer_id, customer_unique_id,
--                         customer_city, customer_state
--   olist_stg.products    product_id, category (English, 'Uncategorised'
--                         where missing), product_weight_g,
--                         product_length_cm, product_height_cm,
--                         product_width_cm
--   olist_stg.sellers     seller_id, seller_city, seller_state
--   olist_stg.reviews     review_id, order_id, review_score (1–5),
--                         review_creation_date
--
-- Run order: sql_01_staging.sql → this script → Power BI refresh.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS olist_dw;

-- ---------------------------------------------------------------------
-- 1. Dim_Date
-- Generated via generate_series (PostgreSQL-native, no recursive CTE
-- needed). Range covers the Olist dataset's known order date span —
-- adjust if your load has different min/max purchase dates.
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS olist_dw."Dim_Date";
CREATE TABLE olist_dw."Dim_Date" AS
SELECT
    CAST(TO_CHAR(d, 'YYYYMMDD') AS INT)   AS date_key,
    d::date                                AS date,
    EXTRACT(YEAR FROM d)::INT              AS year,
    EXTRACT(MONTH FROM d)::INT             AS month_number,
    TRIM(TO_CHAR(d, 'Month'))              AS month_name,
    TO_CHAR(d, 'YYYY-MM')                  AS year_month,
    'Q' || EXTRACT(QUARTER FROM d)::INT    AS quarter,
    TRIM(TO_CHAR(d, 'Day'))                AS day_of_week,
    CASE WHEN EXTRACT(DOW FROM d) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend
FROM generate_series(DATE '2016-01-01', DATE '2018-12-31', INTERVAL '1 day') AS d;

ALTER TABLE olist_dw."Dim_Date" ADD PRIMARY KEY (date_key);

-- ---------------------------------------------------------------------
-- 2. Dim_Customer
-- Grain: one row per customer_unique_id (the true person-level key).
-- Location is taken from the customer's most recent order, since the
-- same physical customer can carry different customer_id / city / state
-- values across orders in the raw data. This is a deliberate decision,
-- not an artefact — documented in the Data Quality Log.
-- first_order_date drives the New Customers KPI and is calculated here
-- so the logic lives in one place, not duplicated in DAX.
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS olist_dw."Dim_Customer";
CREATE TABLE olist_dw."Dim_Customer" AS
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        o.purchase_date,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.purchase_date DESC
        ) AS rn_most_recent
    FROM olist_stg.customers c
    INNER JOIN olist_stg.orders o ON o.customer_id = c.customer_id
),
first_orders AS (
    SELECT
        c.customer_unique_id,
        MIN(o.purchase_date) AS first_order_date
    FROM olist_stg.customers c
    INNER JOIN olist_stg.orders o ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    co.customer_unique_id,
    co.customer_city   AS most_recent_customer_city,
    co.customer_state   AS most_recent_customer_state,
    fo.first_order_date
FROM customer_orders co
LEFT JOIN first_orders fo ON fo.customer_unique_id = co.customer_unique_id
WHERE co.rn_most_recent = 1;

ALTER TABLE olist_dw."Dim_Customer" ADD PRIMARY KEY (customer_unique_id);

-- ---------------------------------------------------------------------
-- 3. Dim_Product
-- Category already translated to English in olist_stg.products per
-- the staging adaptation — selected straight through here.
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS olist_dw."Dim_Product";
CREATE TABLE olist_dw."Dim_Product" AS
SELECT
    product_id,
    category,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM olist_stg.products;

ALTER TABLE olist_dw."Dim_Product" ADD PRIMARY KEY (product_id);

-- ---------------------------------------------------------------------
-- 4. Dim_Seller
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS olist_dw."Dim_Seller";
CREATE TABLE olist_dw."Dim_Seller" AS
SELECT
    seller_id,
    seller_city,
    seller_state
FROM olist_stg.sellers;

ALTER TABLE olist_dw."Dim_Seller" ADD PRIMARY KEY (seller_id);

-- ---------------------------------------------------------------------
-- 5. Fact_Orders
-- Grain: one row per order. customer_id retained for traceability back
-- to the source record; customer_unique_id is the FK Power BI relates
-- to Dim_Customer on. All order statuses are kept (not just delivered)
-- to support the Cancellation Rate KPI.
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS olist_dw."Fact_Orders";
CREATE TABLE olist_dw."Fact_Orders" AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    o.order_status,
    CAST(TO_CHAR(o.purchase_date, 'YYYYMMDD') AS INT) AS purchase_date_key,
    o.purchase_date,
    o.order_approved_at,
    o.delivered_customer_date,
    o.estimated_delivery_date,
    o.is_late,
    o.delivery_days
FROM olist_stg.orders o
INNER JOIN olist_stg.customers c ON c.customer_id = o.customer_id;

ALTER TABLE olist_dw."Fact_Orders" ADD PRIMARY KEY (order_id);
CREATE INDEX idx_fact_orders_customer_unique_id ON olist_dw."Fact_Orders"(customer_unique_id);
CREATE INDEX idx_fact_orders_purchase_date_key ON olist_dw."Fact_Orders"(purchase_date_key);

-- ---------------------------------------------------------------------
-- 6. Fact_OrderItems
-- Grain: one row per order line. Primary fact table for revenue, AOV,
-- category and seller KPIs. customer_unique_id carried through so
-- customer-level revenue slicing doesn't require a join back through
-- Fact_Orders for every visual.
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS olist_dw."Fact_OrderItems";
CREATE TABLE olist_dw."Fact_OrderItems" AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    fo.customer_unique_id,
    oi.price,
    oi.freight_value
FROM olist_stg.order_items oi
INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id;

CREATE INDEX idx_fact_orderitems_order_id ON olist_dw."Fact_OrderItems"(order_id);
CREATE INDEX idx_fact_orderitems_product_id ON olist_dw."Fact_OrderItems"(product_id);
CREATE INDEX idx_fact_orderitems_seller_id ON olist_dw."Fact_OrderItems"(seller_id);
CREATE INDEX idx_fact_orderitems_customer_unique_id ON olist_dw."Fact_OrderItems"(customer_unique_id);

-- ---------------------------------------------------------------------
-- 7. Fact_Reviews
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS olist_dw."Fact_Reviews";
CREATE TABLE olist_dw."Fact_Reviews" AS
SELECT
    review_id,
    order_id,
    review_score,
    review_creation_date
FROM olist_stg.reviews;

CREATE INDEX idx_fact_reviews_order_id ON olist_dw."Fact_Reviews"(order_id);

-- ---------------------------------------------------------------------
-- 8. Build validation
-- Run after every build. Compare row counts and total_revenue against
-- the previous run to catch load failures before they reach Power BI.
-- ---------------------------------------------------------------------

SELECT 'Dim_Date'          AS table_name, COUNT(*) AS row_count FROM olist_dw."Dim_Date"
UNION ALL SELECT 'Dim_Customer',    COUNT(*) FROM olist_dw."Dim_Customer"
UNION ALL SELECT 'Dim_Product',     COUNT(*) FROM olist_dw."Dim_Product"
UNION ALL SELECT 'Dim_Seller',      COUNT(*) FROM olist_dw."Dim_Seller"
UNION ALL SELECT 'Fact_Orders',     COUNT(*) FROM olist_dw."Fact_Orders"
UNION ALL SELECT 'Fact_OrderItems', COUNT(*) FROM olist_dw."Fact_OrderItems"
UNION ALL SELECT 'Fact_Reviews',    COUNT(*) FROM olist_dw."Fact_Reviews";

-- Revenue reconciliation — delivered orders only, per KPI definition 1.1
SELECT
    ROUND(SUM(oi.price)::numeric, 2) AS total_revenue_delivered_orders
FROM olist_dw."Fact_OrderItems" oi
INNER JOIN olist_dw."Fact_Orders" fo ON fo.order_id = oi.order_id
WHERE fo.order_status = 'delivered';

-- Sanity check: unique customers should be materially lower than
-- distinct customer_id count, confirming the fix is doing its job.
SELECT
    (SELECT COUNT(DISTINCT customer_id) FROM olist_stg.customers)        AS distinct_customer_id,
    (SELECT COUNT(*) FROM olist_dw."Dim_Customer")                       AS distinct_customer_unique_id;
