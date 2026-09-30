# Data Quality Log

**Project:** NorthBay Retail — Monthly Commercial Reporting Pack
**Version:** 1.2
**Owner:** Sayanth Rajani Divakaran (Data Analyst)
**Purpose:** Record every data quality issue found or guarded against, the rule applied, and why. Anyone should be able to trace a reported figure back to a documented decision rather than a silent fix inside a query.

> NorthBay Retail is a simulated business context. The data is the public Olist Brazilian E-Commerce dataset.

---

## How to read this log

Each entry records:

- **Where found** — the table and column concerned
- **What it looks like** — the problem, or the risk being guarded against
- **Scale** — the volume found in this load, where it was measured
- **Decision** — exclude, correct, or keep and label
- **Reasoning** — why that decision and not another
- **Downstream effect** — which measures it would affect if left untreated

Schemas: `olist_raw` (raw load), `olist_stg` (cleaned, built by `sql_01_staging.sql`), `olist_dw` (warehouse, built by `sql_02_dimensions_and_facts_postgres.sql`).

**Where a scale says "not quantified", the rule was applied as a precaution and the volume was not measured.** Those entries say so rather than estimating.

---

## 0. Load reconciliation

All nine CSV files loaded into `olist_raw`. Staging row counts were checked against the raw counts and matched.

| Raw table | Rows |
|---|---|
| customers | 99,441 |
| orders | 99,441 |
| order_items | 112,650 |
| order_payments | 103,886 |
| reviews | 99,224 |
| products | 32,951 |
| sellers | 3,095 |
| geolocation | 1,000,163 |
| product_category_name_translation | 71 |

`order_payments` and `geolocation` are loaded but not used by the warehouse.

**Rejection checks in this load:** `orders_rejected` = 0, `order_items_rejected` = 0, `reviews_rejected` = 0. No rows were excluded by any rejection rule.

---

## 1. Orders

### 1.1 Delivered date earlier than purchase date

- **Where found:** `olist_raw.orders`; rows failing the check go to `olist_stg.orders_rejected`
- **What it looks like:** A delivery date before the purchase date — physically impossible, and a sign of a timestamp error at source.
- **Scale:** **0 rows** in this load.
- **Decision:** Guard kept in staging. Any failing row is excluded from `olist_stg.orders` and written to the rejection table, not corrected.
- **Reasoning:** There is no reliable way to know which of the two dates is wrong, so correcting one would be a guess.
- **Downstream effect if untreated:** Negative delivery days would pull down Average Delivery Days and distort On-Time Delivery Rate.

### 1.2 No delivery date on orders that were not delivered

- **Where found:** `olist_raw.orders`
- **What it looks like:** Orders with status such as `shipped`, `canceled`, `unavailable` or `processing` have no delivery date. This is expected, not an error.
- **Scale:** Equal to the non-delivered share of orders.
- **Decision:** Kept. `delivery_days` is NULL for these orders. Delivery and revenue measures filter to `delivered` orders themselves.
- **Reasoning:** These orders are needed for the Cancellation Rate, whose denominator is all orders regardless of status. Dropping them would break that measure.
- **Downstream effect if untreated:** None when handled this way. Recorded so that a future change does not "clean" these rows away and silently break cancellation reporting.

### 1.3 Order status values

- **Where found:** `olist_raw.orders.order_status`
- **What it looks like:** Risk that status values differ in case or spacing between exports, so that a filter on `'delivered'` misses some rows.
- **Scale:** No inconsistency observed. Status filters in SQL and DAX reconcile exactly: delivered-order revenue is 13,221,498.11 BRL in both.
- **Decision:** No transformation added. If a future load introduces inconsistent values, add `LOWER(TRIM(...))` to staging.
- **Reasoning:** Adding a fix for a problem that does not exist in the data adds complexity without benefit. The reconciliation check will catch it if it appears.

### 1.4 Sparse and incomplete months at the edges of the dataset

- **Where found:** `Fact_Orders.purchase_date`, visible in the monthly trend charts
- **What it looks like:** Order volume in late 2016 is very low, and the final months of the dataset are incomplete.
- **Scale:** Not quantified; visible as near-zero bars at both ends of the full-history trend.
- **Decision:** Kept in the warehouse. The report opens on 1 January 2017 – 31 July 2018, and the most recent partial month is excluded from trend visuals.
- **Reasoning:** The rows are genuine orders and belong in lifetime figures. They distort trends and month-on-month percentages, so they are kept out of the default view rather than out of the data.
- **Downstream effect if untreated:** False growth spikes at the start of trends and a false collapse at the end.

---

## 2. Order items

### 2.1 Zero or negative price

- **Where found:** `olist_raw.order_items`; rows failing the check go to `olist_stg.order_items_rejected`
- **What it looks like:** An order line with `price <= 0`.
- **Scale:** **0 rows** in this load.
- **Decision:** Guard kept in staging. Any failing row is excluded and logged.
- **Reasoning:** A non-positive price is far more likely to be an extraction fault than a real sale. Including it would understate average order value and distort category revenue.
- **Downstream effect if untreated:** Lower Total Revenue and Average Order Value, and a distorted category mix.

### 2.2 Duplicate order lines

- **Where found:** `olist_stg.order_items`
- **What it looks like:** Two rows sharing the same `order_id` and `order_item_id`.
- **Scale:** Not checked as a separate test in this build. Staging row counts match raw, so staging introduced no duplicates; duplicates in the source itself have not been ruled out.
- **Decision:** Recommended check for future loads:

```sql
SELECT order_id, order_item_id, COUNT(*)
FROM olist_stg.order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;
```

- **Reasoning:** Order-line grain underpins revenue and units. A duplicate would double-count revenue without raising any error.

---

## 3. Customers

### 3.0 customer_id is order-level, not person-level

- **Where found:** `olist_raw.customers`, during initial exploration before staging was built.
- **What it looks like:** The source issues a new `customer_id` for every order. The same physical person placing three orders has three different `customer_id` values. `customer_unique_id` is the value that stays the same for a person across all their orders.
- **Scale:** Structural — it affects the whole customer table. `COUNT(DISTINCT customer_unique_id)` is lower than `COUNT(DISTINCT customer_id)`, and the gap is the repeat-customer volume. Validated in the warehouse: **93,358** customers with a delivered order, of whom **2,801** placed more than one — a lifetime repeat purchase rate of **3.0%**.
- **Decision:** `Dim_Customer` is built at `customer_unique_id` grain. `customer_unique_id` is carried onto `Fact_Orders` and `Fact_OrderItems`. `customer_id` is kept on `Fact_Orders` only for traceability. Every customer measure — Active, New, Returning, Repeat Customers, Repeat Purchase Rate — counts `customer_unique_id`.
- **Reasoning:** At `customer_id` grain no customer ever appears twice, so every order looks like a first purchase.
- **Downstream effect if untreated:** New Customers would equal Active Customers in every period, Returning Customers would always be zero, and Repeat Purchase Rate would read 0% — broken metrics that would still look plausible on a dashboard.

### 3.0.1 Customer location varies across orders for the same person

- **Where found:** `olist_raw.customers`, while resolving 3.0. City and state are recorded per `customer_id` — that is, per order — so one person can carry different locations on different orders.
- **What it looks like:** Two orders for the same `customer_unique_id` with different states.
- **Scale:** Not quantified. It can only affect customers with more than one order, a subset of the 2,801 repeat customers.
- **Decision:** `Dim_Customer.most_recent_customer_city` and `most_recent_customer_state` are taken from the customer's most recent order by purchase date.
- **Reasoning:** Regional reporting needs one location per customer. The most recent order best reflects where the customer is now. Without a stated rule, the location would depend on whichever row happened to be read first.
- **Downstream effect if untreated:** Revenue by customer state could change between runs with no change in the data.

### 3.1 State code formatting

- **Where found:** `olist_raw.customers.customer_state`
- **What it looks like:** Risk that the same state appears with different case or stray spaces, splitting one state into several groups.
- **Scale:** Not quantified.
- **Decision:** Standardised in staging with `UPPER(TRIM(...))` as a precaution.
- **Reasoning:** Low cost, and it prevents a failure that is easy to miss by eye.
- **Downstream effect if untreated:** Regional totals split across near-duplicate labels.

---

## 4. Products

### 4.1 Missing product category

- **Where found:** `olist_raw.products.product_category_name`
- **What it looks like:** Some products have no category.
- **Scale:** Not quantified in this log. To measure:

```sql
SELECT COUNT(*) FROM olist_raw.products
WHERE product_category_name IS NULL OR TRIM(product_category_name) = '';
```

- **Decision:** Labelled `Uncategorised` rather than dropped.
- **Reasoning:** These are real sales. Dropping them would understate Total Revenue and stop category revenue reconciling to the total.
- **Downstream effect if untreated:** If dropped, revenue is understated and category shares do not sum to 100%. If left NULL, visuals show blank labels that look like a bug.

### 4.2 Category names translated to English

- **Where found:** `olist_raw.products` joined to `olist_raw.product_category_name_translation` (71 rows) in staging
- **What it looks like:** Source category names are in Portuguese.
- **Decision:** English names from the translation table are used in `Dim_Product.category`. Names are used exactly as the translation table supplies them — including its own spelling irregularities, such as `costruction_tools_tools`, which appears in the report.
- **Reasoning:** Correcting the source table's spelling by hand would make the report disagree with the source data and with anyone else's analysis of it.

---

## 5. Sellers

### 5.1 State code formatting

- **Where found:** `olist_raw.sellers.seller_state`
- **Decision:** Same treatment as 3.1 — `UPPER(TRIM(...))` in staging.
- **Reasoning:** The same class of problem is solved the same way in every table.

---

## 6. Reviews

### 6.1 Review score outside 1–5

- **Where found:** `olist_raw.reviews.review_score`; rows failing the check go to `olist_stg.reviews_rejected`
- **What it looks like:** A score outside the 1–5 scale.
- **Scale:** **0 rows** in this load.
- **Decision:** Guard kept in staging. Any failing row is excluded and logged.
- **Reasoning:** A score outside the scale cannot be a genuine rating.
- **Downstream effect if untreated:** A distorted Average Review Score and Late Delivery Review Gap, both used in the findings memo.

### 6.2 Review coverage — assumption tested and overturned

- **Where found:** Comparing reviewed orders with delivered orders in `olist_dw`.
- **Initial assumption (incorrect):** Reviews were assumed to be voluntary and so to cover only a subset of delivered orders — the usual pattern for customer feedback, and the basis on which the original KPI watch-outs were written.
- **What was found:** Coverage is effectively complete. The validation query returned **95,832 reviewed orders out of 96,478 delivered orders = 99.33%**. The Power BI `Review Coverage` measure returned the same figure independently. Why coverage is this high is not determinable from the data available and is not claimed here.
- **Validation query:**

```sql
SELECT
    COUNT(DISTINCT r.order_id) AS reviewed,
    COUNT(DISTINCT o.order_id) AS delivered,
    ROUND(100.0 * COUNT(DISTINCT r.order_id) / COUNT(DISTINCT o.order_id), 2) AS coverage_pct
FROM olist_dw."Fact_Orders" o
LEFT JOIN olist_dw."Fact_Reviews" r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';
```

- **Decision:** No data treatment needed. The interpretation changed: Average Review Score is documented as representative of the delivered-order population rather than a self-selected subset. Review Coverage is kept as a monitoring check; a drop below the 99.33% baseline on a future load signals an upstream problem.
- **Reasoning for recording a non-issue:** The assumption was plausible, written into the documentation, and wrong. Left untested, every review-based finding would have carried an unnecessary caveat. Testing an assumption that turns out to be false is as much a data quality activity as catching a bad row.
- **Downstream effect:** Strengthens the Late Delivery Review Gap finding. With coverage at 99.33%, review-participation bias is unlikely to explain the gap materially.

---

## 7. Rules applied throughout

| Rule | Applied to | Reasoning |
|---|---|---|
| Reject and log rather than silently drop | Orders, order items, reviews | Every excluded row can be inspected in a `*_rejected` table |
| Trim and standardise case on grouping text | Customer state, seller state | Prevents one group splitting into several |
| Label missing categories; never drop real revenue | Product category | Keeps totals reconciled and gaps visible |
| Never impute a rating | Reviews | A customer opinion that was not given is not created |
| Count people, not orders | Customers | `customer_unique_id` is the only valid customer key |

## 8. Monitoring after each load

1. Run the validation queries at the end of `sql_01_staging.sql` and `sql_02_dimensions_and_facts_postgres.sql`.
2. Run section 0 of `sql_03_business_queries.sql` and compare totals with the report.
3. Re-run the review coverage query in 6.2 and compare with the 99.33% baseline.

A sustained rise in any rejected-row count indicates an upstream export problem. Raise it before the report is published rather than fixing it silently in SQL.

## Change control

| Version | Change |
|---|---|
| 1.0 | Initial data quality log for first build |
| 1.1 | Entry 6.2 rewritten: review-coverage assumption tested in SQL and overturned (99.33%); validation query recorded |
| 1.2 | Updated to the final build: `olist_raw` / `olist_stg` / `olist_dw` schema names; load reconciliation and rejection results recorded (all three checks returned 0 rows); guard entries 1.1, 2.1 and 6.1 restated as guards with 0 rows found; validated customer figures added to 3.0 (93,358 customers, 2,801 repeat, 3.0%); entries 1.4 (dataset edges) and 4.2 (category translation) added; unmeasured scales marked "not quantified"; monitoring steps reference the final SQL filenames; dependence on an unwritten runbook removed |
