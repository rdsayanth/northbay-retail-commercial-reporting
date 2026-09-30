CREATE SCHEMA IF NOT EXISTS olist_stg;
-- =============================================
-- OLIST STAGING / CLEANING LAYER
-- PostgreSQL version
-- =============================================


-- 1. ORDERS: identify impossible delivery dates

DROP TABLE IF EXISTS olist_stg.orders_rejected;

CREATE TABLE olist_stg.orders_rejected AS
SELECT
    order_id,
    order_purchase_timestamp,
    order_delivered_customer_date,
    'delivered_before_purchase' AS rejection_reason
FROM olist_raw.orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_purchase_timestamp;


-- Clean orders table

DROP TABLE IF EXISTS olist_stg.orders;

CREATE TABLE olist_stg.orders AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp::DATE AS purchase_date,
    o.order_approved_at,
    o.order_delivered_customer_date::DATE AS delivered_customer_date,
    o.order_estimated_delivery_date::DATE AS estimated_delivery_date,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN 1
        ELSE 0
    END AS is_late,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN
            o.order_delivered_customer_date::DATE
            - o.order_purchase_timestamp::DATE
        ELSE NULL
    END AS delivery_days

FROM olist_raw.orders o

WHERE NOT EXISTS (
    SELECT 1
    FROM olist_stg.orders_rejected r
    WHERE r.order_id = o.order_id
);


-- 2. ORDER ITEMS: reject zero/negative prices

DROP TABLE IF EXISTS olist_stg.order_items_rejected;

CREATE TABLE olist_stg.order_items_rejected AS
SELECT
    order_id,
    order_item_id,
    price,
    'non_positive_price' AS rejection_reason
FROM olist_raw.order_items
WHERE price <= 0;


DROP TABLE IF EXISTS olist_stg.order_items;

CREATE TABLE olist_stg.order_items AS
SELECT
    order_id,
    order_item_id,
    product_id,
    seller_id,
    price,
    freight_value
FROM olist_raw.order_items
WHERE price > 0;


-- 3. CUSTOMERS
-- Keep customer_unique_id so repeat customers can be identified correctly

DROP TABLE IF EXISTS olist_stg.customers;

CREATE TABLE olist_stg.customers AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    TRIM(customer_city) AS customer_city,
    UPPER(TRIM(customer_state)) AS customer_state
FROM olist_raw.customers;


-- 4. PRODUCTS
-- Translate Portuguese category names to English where available

DROP TABLE IF EXISTS olist_stg.products;

CREATE TABLE olist_stg.products AS
SELECT
    p.product_id,

    COALESCE(
        NULLIF(TRIM(t.product_category_name_english), ''),
        NULLIF(TRIM(p.product_category_name), ''),
        'Uncategorised'
    ) AS category,

    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm

FROM olist_raw.products p

LEFT JOIN olist_raw.product_category_name_translation t
    ON p.product_category_name = t.product_category_name;


-- 5. SELLERS

DROP TABLE IF EXISTS olist_stg.sellers;

CREATE TABLE olist_stg.sellers AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    TRIM(seller_city) AS seller_city,
    UPPER(TRIM(seller_state)) AS seller_state
FROM olist_raw.sellers;


-- 6. REVIEWS: reject invalid review scores

DROP TABLE IF EXISTS olist_stg.reviews_rejected;

CREATE TABLE olist_stg.reviews_rejected AS
SELECT
    review_id,
    order_id,
    review_score,
    'score_out_of_range' AS rejection_reason
FROM olist_raw.reviews
WHERE review_score NOT BETWEEN 1 AND 5;


DROP TABLE IF EXISTS olist_stg.reviews;

CREATE TABLE olist_stg.reviews AS
SELECT
    review_id,
    order_id,
    review_score,
    review_creation_date::DATE AS review_creation_date
FROM olist_raw.reviews
WHERE review_score BETWEEN 1 AND 5;


-- 7. DATA QUALITY CHECK

SELECT
    'orders_rejected' AS check_name,
    COUNT(*) AS row_count
FROM olist_stg.orders_rejected

UNION ALL

SELECT
    'order_items_rejected',
    COUNT(*)
FROM olist_stg.order_items_rejected

UNION ALL

SELECT
    'reviews_rejected',
    COUNT(*)
FROM olist_stg.reviews_rejected;