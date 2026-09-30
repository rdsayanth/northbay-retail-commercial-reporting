# Data Model — Star Schema

**Project:** NorthBay Retail — Monthly Commercial Reporting Pack
**Version:** 2.0
**Built by:** `sql_02_dimensions_and_facts_postgres.sql`, in PostgreSQL schema `olist_dw`

> NorthBay Retail is a simulated business context. The data is the public Olist Brazilian E-Commerce dataset.

---

## Pipeline

```
Olist CSVs (9 files)
   ↓  loaded as-is
olist_raw    — raw tables
   ↓  sql_01_staging.sql
olist_stg    — cleaned and standardised; rejection tables for invalid rows
   ↓  sql_02_dimensions_and_facts_postgres.sql
olist_dw     — star schema: 4 dimensions, 3 fact tables
   ↓  Import mode
Power BI     — 35 DAX measures, 5 report pages
```

Power BI connects to `olist_dw` only. Nothing upstream of it is referenced by the report.

## Why a star schema, not a flat table

The raw exports are flat files. Loading them into Power BI as a single wide table is the quickest way to a dashboard, but it breaks counting: an order with five items appears five times, so order and customer counts are wrong unless every measure is written defensively.

A star schema avoids that. Each fact table sits at the true grain of its business event, and dimension tables describe it. Every measure in the KPI definition document is written against this model.

## Schema

Arrows show the direction filters travel: from the one side of each relationship to the many side.

```
   Dim_Date        Dim_Customer
        \              /
         ▼            ▼
          Fact_Orders  ──────────▶  Fact_Reviews
               │
               ▼
        Fact_OrderItems
          ▲          ▲
          │          │
    Dim_Product   Dim_Seller
```

- **`Fact_OrderItems`** is the primary fact table: one row per order line. Revenue, units, category and seller measures are based on it.
- **`Fact_Orders`** holds order-level attributes that exist once per order: status, dates, delivery outcome.
- **`Fact_Reviews`** holds reviews at review grain, related to orders through `order_id`.

## Table definitions

### Dim_Date

Grain: one row per calendar day, 1 January 2016 – 31 December 2018. Generated with `generate_series`, not taken from the fact tables.

| Column | Type | Notes |
|---|---|---|
| `date_key` | int | YYYYMMDD. Primary key |
| `date` | date | Marked as the date column when `Dim_Date` is marked as the Power BI date table |
| `year` | int | |
| `month_number` | int | |
| `month_name` | text | |
| `year_month` | text | e.g. `2017-03`; used on chart axes |
| `quarter` | text | e.g. `Q1` |
| `day_of_week` | text | |
| `is_weekend` | boolean | |

A generated, contiguous date table is required for the time-intelligence measures. `Revenue Previous Month` and `Revenue Previous Year` both use `DATEADD`. `SAMEPERIODLASTYEAR` was tried first for the prior-year measure but caused a circular-dependency error in this model; `DATEADD(..., -1, YEAR)` is equivalent and is what the model uses.

### Dim_Customer

Grain: **one row per `customer_unique_id`** — one row per physical customer.

| Column | Type | Notes |
|---|---|---|
| `customer_unique_id` | text | Primary key. The person-level customer key |
| `most_recent_customer_city` | text | City on the customer's most recent order |
| `most_recent_customer_state` | text | State on the customer's most recent order; used for all regional reporting |
| `first_order_date` | date | Date of the customer's first **delivered** order; drives the New Customers measure. NULL for customers with no delivered order |

The source issues a new `customer_id` for every order, so `customer_id` cannot be the customer grain: no value ever repeats, and every order would look like a first purchase. `customer_id` is kept on `Fact_Orders` only to trace a row back to the source record. See Data Quality Log entries 3.0 and 3.0.1.

### Dim_Product

Grain: one row per `product_id`.

| Column | Type | Notes |
|---|---|---|
| `product_id` | text | Primary key |
| `category` | text | English category name from the translation table; missing categories labelled `Uncategorised` |
| `product_weight_g` | numeric | |
| `product_length_cm` | numeric | |
| `product_height_cm` | numeric | |
| `product_width_cm` | numeric | |

### Dim_Seller

Grain: one row per `seller_id`.

| Column | Type | Notes |
|---|---|---|
| `seller_id` | text | Primary key |
| `seller_city` | text | |
| `seller_state` | text | |

### Fact_Orders

Grain: one row per `order_id`. **All order statuses are kept**, because the cancellation rate is defined against all orders. Revenue and delivery measures filter to `delivered` themselves.

| Column | Type | Notes |
|---|---|---|
| `order_id` | text | Primary key |
| `customer_id` | text | Order-level source key, kept for traceability only. **Not** used for any relationship or customer count |
| `customer_unique_id` | text | Relates to `Dim_Customer` |
| `order_status` | text | e.g. `delivered`, `canceled`, `unavailable` |
| `purchase_date_key` | int | Relates to `Dim_Date` |
| `purchase_date` | date | Order date used throughout the pack |
| `order_approved_at` | timestamp | |
| `delivered_customer_date` | date | NULL for orders not delivered |
| `estimated_delivery_date` | date | Estimate given to the customer |
| `is_late` | 0/1 | 1 when delivered after the estimated delivery date |
| `delivery_days` | integer | Calendar days from purchase to delivery; NULL when there is no delivery date |

Indexed on `customer_unique_id` and `purchase_date_key`.

### Fact_OrderItems

Grain: one row per order line (`order_id` + `order_item_id`).

| Column | Type | Notes |
|---|---|---|
| `order_id` | text | Relates to `Fact_Orders` |
| `order_item_id` | int | Line number within the order |
| `product_id` | text | Relates to `Dim_Product` |
| `seller_id` | text | Relates to `Dim_Seller` |
| `customer_unique_id` | text | Carried from `Fact_Orders` so customer counts can be taken directly from this table. There is **no** relationship on this column; customer filters reach it through `Dim_Customer → Fact_Orders → Fact_OrderItems` |
| `price` | numeric | Revenue basis; excludes freight |
| `freight_value` | numeric | |

Indexed on `order_id`, `product_id`, `seller_id` and `customer_unique_id`.

### Fact_Reviews

Grain: one row per review.

| Column | Type | Notes |
|---|---|---|
| `review_id` | text | |
| `order_id` | text | Relates to `Fact_Orders` |
| `review_score` | int | 1–5 |
| `review_creation_date` | date | |

## Relationships

All six relationships are many-to-one with **single-direction** cross-filtering.

| From (many side) | To (one side) | Filter direction |
|---|---|---|
| `Fact_Orders[purchase_date_key]` | `Dim_Date[date_key]` | Dim_Date → Fact_Orders |
| `Fact_Orders[customer_unique_id]` | `Dim_Customer[customer_unique_id]` | Dim_Customer → Fact_Orders |
| `Fact_OrderItems[order_id]` | `Fact_Orders[order_id]` | Fact_Orders → Fact_OrderItems |
| `Fact_OrderItems[product_id]` | `Dim_Product[product_id]` | Dim_Product → Fact_OrderItems |
| `Fact_OrderItems[seller_id]` | `Dim_Seller[seller_id]` | Dim_Seller → Fact_OrderItems |
| `Fact_Reviews[order_id]` | `Fact_Orders[order_id]` | Fact_Orders → Fact_Reviews |

Bi-directional filtering was rejected. With three fact tables it could create ambiguous filter paths and silently produce incorrect results. Single-direction relationships keep every measure predictable.

## Filter propagation — what each slicer reaches

| Slicer | Reaches `Fact_Orders` | Reaches `Fact_OrderItems` | Reaches `Fact_Reviews` |
|---|---|---|---|
| Period (`Dim_Date`) | Yes | Yes, via `Fact_Orders` | Yes, via `Fact_Orders` |
| Customer state (`Dim_Customer`) | Yes | Yes, via `Fact_Orders` | Yes, via `Fact_Orders` |
| Category (`Dim_Product`) | **No** | Yes | **No** |
| Seller state (`Dim_Seller`) | **No** | Yes | **No** |

Category and seller filters stop at `Fact_OrderItems`, because it sits on the many side of its relationship to `Fact_Orders` and filters do not travel back up. Two consequences follow, both handled in the KPI definition document (sections 3 and 4):

- **Seller-level delivery and review measures use `TREATAS`.** They take the order IDs visible in the current filter context from `Fact_OrderItems` and apply them as a filter on `Fact_Orders` or `Fact_Reviews`. Without this, every seller would show the marketplace-wide figure. `Reviewed Orders` uses the same pattern so that Review Coverage compares matching populations under any filter.
- **The remaining delivery and review measures are order-level by design** and respond only to period and customer state. The Delivery & Satisfaction page therefore carries only those two slicers; the category and seller state slicers are removed from it.

## Validated figures

| Check | Result |
|---|---|
| Delivered orders | 96,478 |
| Total revenue, delivered orders, full history | 13,221,498.11 BRL |
| Customers with a delivered order (`customer_unique_id`) | 93,358 |
| Customers with more than one delivered order | 2,801 (3.0%) |
| Delivered orders with a review | 95,832 (99.33%) |

Validation queries are at the end of `sql_02_dimensions_and_facts_postgres.sql` and in section 0 of `sql_03_business_queries.sql`.

## Change control

| Version | Change |
|---|---|
| 1.0 | Initial design |
| 2.0 | Updated to the implemented warehouse: `Dim_Customer` at `customer_unique_id` grain with most-recent location; `customer_unique_id` added to `Fact_Orders` and `Fact_OrderItems`; schema diagram and relationships corrected; filter-propagation table and `TREATAS` handling added; `DATEADD` replaces `SAMEPERIODLASTYEAR`; validated figures recorded |
