# KPI Definition Document

**Project:** NorthBay Retail — Monthly Commercial Reporting Pack
**Version:** 2.1
**Owner:** Sayanth Rajani Divakaran (Data Analyst)
**Purpose:** Single agreed source of truth for how every metric in the reporting pack is calculated. Any metric not defined in this document must not appear in the report.

**Changes in v2.1:** Document reconciled against the final implemented Power BI model. New Customers, Repeat Customers and Reviewed Orders updated to the implemented DAX (the v2.0 versions had propagation faults). Four seller measures added for Page 4 — Total Sellers, Avg Seller Delivery Days, Seller Late Delivery Rate and Seller Cancellation Rate — and the existing seller review measures reorganised into section 3. Filter-propagation rule documented in section 3, with a scope note added to section 4. Measure inventory corrected from 30 to 35 with filter scope recorded per measure. `Revenue MoM % Change (Material)` added (1.7) to suppress small-base distortion on the Executive Summary category table. Review coverage assumption corrected: v2.0 assumed reviews were voluntary and partial; SQL validation showed 95,832 reviewed of 96,478 delivered orders = 99.33%.

**Changes in v2.0:** DAX updated to match the implemented Power BI model. Customer metrics now explicitly keyed on `customer_unique_id`. Repeat Purchase Rate reimplemented (v1.0 logic was fragile). Helper measures documented explicitly. Delivered-order filtering standardised across all measures.

---

## How to read this document

Each KPI is defined with:

- **Business definition** — what it means in plain language, for a non-technical user.
- **DAX** — the exact implemented measure.
- **Grain** — the level the metric is calculated at.
- **Watch-outs** — where the metric can mislead.

Measures marked **[helper]** are building blocks referenced by other measures. They exist to keep logic in one place and should generally not be placed on a visual on their own.

## Global rules

These apply to every metric unless a definition overrides them explicitly.

| Rule | Decision |
|---|---|
| Revenue-eligible orders | Only orders with status `delivered` |
| Delivered filter placement | Applied as a predicate on `'Fact_Orders'[order_status]` inside each base measure, so it propagates consistently from the one-side of the relationship |
| Date basis | Purchase timestamp, allocated to the month in which the purchase occurred |
| Revenue basis | Item price, excluding freight |
| Freight treatment | Reported separately as a cost metric, never netted against revenue |
| Cancelled orders | Excluded from revenue, reported separately as cancellation rate |
| Customer key | `customer_unique_id` — the true person-level key. `customer_id` is order-level in the source system and must never be used for customer counting. See Data Quality Log 3.0 |
| Missing category | Grouped as `Uncategorised`, never dropped |
| Partial months | Most recent incomplete month excluded from trend visuals and flagged in the report footer |
| Currency | BRL (Olist source data), applied consistently across all deliverables |

---

## 1. Revenue and commercial performance

### 1.1 Total Revenue

- **Business definition:** The value of goods sold in delivered orders, excluding delivery charges.
- **Grain:** Order line, aggregated to any level
- **Owner:** Head of Commercial

```dax
Total Revenue = 
CALCULATE(
    SUM('Fact_OrderItems'[price]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Watch-outs:** Because cancelled orders are excluded rather than netted off, revenue will not tie to a raw system total that includes all order statuses. This is intentional and must be stated wherever the figure is published.

### 1.2 Total Orders

- **Business definition:** The number of distinct delivered orders in the period.
- **Grain:** Order

```dax
Total Orders = 
CALCULATE(
    DISTINCTCOUNT('Fact_OrderItems'[order_id]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Watch-outs:** An order containing five items counts once. Never use the order-item row count as an order count.

### 1.3 Average Order Value (AOV)

- **Business definition:** Average revenue generated per delivered order.
- **Grain:** Order
- **Owner:** Head of Commercial

```dax
Average Order Value = DIVIDE([Total Revenue], [Total Orders])
```

- **Watch-outs:** Sensitive to a small number of high-value orders. Report alongside median order value where the distribution is skewed.

### 1.4 Units Sold

- **Business definition:** The number of individual items sold in delivered orders.
- **Grain:** Order line

```dax
Units Sold = 
CALCULATE(
    COUNTROWS('Fact_OrderItems'),
    'Fact_Orders'[order_status] = "delivered"
)
```

### 1.5 Revenue Previous Month **[helper]**

```dax
Revenue Previous Month = 
CALCULATE(
    [Total Revenue],
    DATEADD('Dim_Date'[date], -1, MONTH)
)
```

### 1.6 Revenue MoM % Change

- **Business definition:** Percentage change in revenue compared with the previous calendar month.

```dax
Revenue MoM % Change = 
IF(
    NOT ISBLANK([Revenue Previous Month]),
    DIVIDE([Total Revenue] - [Revenue Previous Month], [Revenue Previous Month])
)
```

- **Watch-outs:** Months have unequal numbers of trading days and weekends. A month-on-month decline is not automatically a performance decline — check against the same month last year before drawing conclusions. The `IF` wrapper suppresses the measure in the first period of the dataset rather than showing a misleading value.

### 1.7 Revenue MoM % Change (Material)

- **Business definition:** Month-on-month revenue change, shown only where the category (or other row) has at least 50,000 BRL of revenue in the selected period.
- **Grain:** Any level; used on the Executive Summary category table
- **Owner:** Head of Commercial

```dax
Revenue MoM % Change (Material) = 
IF(
    [Total Revenue] >= 50000,
    [Revenue MoM % Change]
)
```

- **Purpose:** Suppresses small-base distortion. Sorted by raw MoM %, the category table was topped by categories with around 1,000 BRL of revenue showing changes above +250% — a handful of extra orders producing a headline percentage.
- **Implementation note:** The measure suppresses the **metric**, not the **row**. Categories below 50,000 BRL remain in the table with their revenue and share visible; only their MoM % returns blank. Blanks sort to the bottom under a descending sort, so the largest movers among material categories rise to the top.
- **Why not a visual-level filter:** A visual filter of Total Revenue > 50,000 was tested and rejected. It removes rows from the visual, so the table total recalculates over the remaining rows only (11.72M / 95% rather than 12.34M / 100%) and no longer reconciles with the page's Total Revenue KPI card. Suppressing the metric keeps every row and preserves reconciliation. At total level, Total Revenue clears the threshold, so the Total row still shows the overall MoM %.
- **Threshold:** 50,000 BRL is a judgement threshold chosen to exclude categories whose monthly movement is dominated by a few orders. It is not statistically derived. If the threshold is changed, record the new value here.
- **Relationship to 1.6:** `Revenue MoM % Change` (1.6) is unchanged and remains the measure used wherever no suppression is wanted, including the Executive Summary MoM card.
- **Watch-outs:** A blank in this column means "below materiality threshold", not "no change" and not "no data". Same pattern as the 20-review threshold on `Avg Seller Review Score` (3.3).

### 1.8 Revenue Previous Year **[helper]**

```dax
Revenue Previous Year = 
CALCULATE(
    [Total Revenue],
    DATEADD('Dim_Date'[date], -1, YEAR)
)
```

- **Implementation note:** `SAMEPERIODLASTYEAR` was the original v1.0 approach but produced a circular dependency error in this model. `DATEADD(..., -1, YEAR)` is functionally equivalent and is the implemented version.

### 1.9 Revenue YoY % Change

- **Business definition:** Percentage change in revenue compared with the same month in the previous year.

```dax
Revenue YoY % Change = 
IF(
    NOT ISBLANK([Revenue Previous Year]),
    DIVIDE([Total Revenue] - [Revenue Previous Year], [Revenue Previous Year])
)
```

- **Watch-outs:** Returns blank where no prior-year data exists — suppressed rather than displayed as 0% or -100%.

### 1.10 Category Revenue Share

- **Business definition:** The proportion of total revenue contributed by a product category.
- **Grain:** Category
- **Owner:** Category Managers

```dax
Category Revenue Share = 
DIVIDE(
    [Total Revenue],
    CALCULATE([Total Revenue], ALL('Dim_Product'))
)
```

- **Watch-outs:** Share moves when other categories move. A category can lose share while growing in absolute revenue — always present share next to absolute revenue.

### 1.11 Freight Cost Ratio

- **Business definition:** Delivery charges as a proportion of goods revenue.
- **Owner:** Operations Manager

```dax
Freight Cost Ratio = 
DIVIDE(
    CALCULATE(
        SUM('Fact_OrderItems'[freight_value]),
        'Fact_Orders'[order_status] = "delivered"
    ),
    [Total Revenue]
)
```

- **Watch-outs:** Heavily influenced by product weight and distance. Compare within category and region, not across the whole business.

---

## 2. Customer behaviour

All measures in this section are keyed on `customer_unique_id`. See Data Quality Log 3.0 for why `customer_id` cannot be used.

### 2.1 Active Customers

- **Business definition:** The number of distinct physical customers who placed at least one delivered order in the period.
- **Grain:** Customer per period
- **Owner:** Head of Marketing

```dax
Active Customers = 
CALCULATE(
    DISTINCTCOUNT('Fact_OrderItems'[customer_unique_id]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Watch-outs:** This is the definition that resolves the Commercial vs Marketing discrepancy. **Agreed standard: delivered orders only.** Active customers do not sum across months — a customer active in January and February is one customer in a two-month view, not two.

### 2.2 New Customers

- **Business definition:** Customers whose first ever delivered order falls within the period.
- **Grain:** Customer (`customer_unique_id`)
- **Owner:** Head of Marketing

```dax
New Customers = 
VAR MinDate = MIN('Dim_Date'[date])
VAR MaxDate = MAX('Dim_Date'[date])
VAR ActiveCusts = 
    CALCULATETABLE(
        VALUES('Fact_OrderItems'[customer_unique_id]),
        'Fact_Orders'[order_status] = "delivered"
    )
RETURN
COUNTROWS(
    FILTER(
        ActiveCusts,
        VAR ThisCust = 'Fact_OrderItems'[customer_unique_id]
        VAR FirstOrder = 
            CALCULATE(
                MIN('Dim_Customer'[first_order_date]),
                'Dim_Customer'[customer_unique_id] = ThisCust
            )
        RETURN FirstOrder >= MinDate && FirstOrder <= MaxDate
    )
)
```

- **Implementation note:** `first_order_date` lives in `Dim_Customer`, which has no relationship to `Dim_Date`, so the measure reads the active date range explicitly rather than relying on filter propagation. Critically, it counts only customers who were **active in the period** AND whose first-ever order fell in that period. An earlier version counted anyone whose `first_order_date` fell in range without requiring activity in that range, which meant New Customers and Active Customers were computed over the same population and Returning Customers was always exactly zero.
- **Watch-outs:** Every customer is "new" in the first month of the dataset, which inflates the earliest period. Exclude the first month from new-customer trend visuals.

### 2.3 Returning Customers

- **Business definition:** Active customers in the period who had placed at least one delivered order before the period began.
- **Grain:** Customer (`customer_unique_id`)

```dax
Returning Customers = [Active Customers] - [New Customers]
```

### 2.4 Repeat Customers **[helper]**

- **Business definition:** Count of physical customers with more than one delivered order in the selected window.

```dax
Repeat Customers = 
COUNTROWS(
    FILTER(
        VALUES('Fact_OrderItems'[customer_unique_id]),
        CALCULATE(
            DISTINCTCOUNT('Fact_OrderItems'[order_id]),
            'Fact_Orders'[order_status] = "delivered"
        ) > 1
    )
)
```

- **Implementation note:** Iterates `Fact_OrderItems`, not `Dim_Customer`. An earlier version iterated `VALUES('Dim_Customer'[customer_unique_id])` and counted orders on `Fact_Orders`, which made it blind to Category and Seller State filters while `[Active Customers]` remained filter-aware — under a narrow category filter the resulting Repeat Purchase Rate could exceed 100%. v1.0 of this document used `[Orders per Customer] > 1`, an average measure applied as if it were a per-customer count; that was replaced first.

### 2.5 Repeat Purchase Rate

- **Business definition:** The share of physical customers who have placed more than one delivered order.
- **Grain:** Customer (`customer_unique_id`)
- **Owner:** Head of Marketing

```dax
Repeat Purchase Rate = DIVIDE([Repeat Customers], [Active Customers])
```

- **Watch-outs:** Highly sensitive to the time window selected. A one-month window will always show a low rate because there is little opportunity to repeat. Report on a rolling 12-month basis and label the window on the visual.

### 2.6 Orders per Customer

```dax
Orders per Customer = DIVIDE([Total Orders], [Active Customers])
```

### 2.7 Revenue per Customer

```dax
Revenue per Customer = DIVIDE([Total Revenue], [Active Customers])
```

### 2.8 Revenue by Region

- **Business definition:** Revenue attributed to the customer's most recent registered state.
- **Implementation:** `[Total Revenue]` sliced by `'Dim_Customer'[most_recent_customer_state]` — no separate measure required.
- **Watch-outs:** Attributed to the customer's location, not the seller's or the delivery address. Where a customer's location changed between orders, the most recent is used — see Data Quality Log 3.0.1.

---

## 3. Seller performance

Seller revenue and order counts are `[Total Revenue]` and `[Total Orders]` sliced by `'Dim_Seller'` — no separate measures required.

### Filter propagation — why this section duplicates some metrics

All relationships in this model are single-direction, flowing from the one side to the many side:

```
Dim_Product  → Fact_OrderItems
Dim_Seller   → Fact_OrderItems
Dim_Customer → Fact_Orders
Dim_Date     → Fact_Orders
Fact_Orders  → Fact_OrderItems
Fact_Orders  → Fact_Reviews
```

The consequence: `Dim_Seller` and `Dim_Product` reach **only** `Fact_OrderItems`. They do not reach `Fact_Orders` or `Fact_Reviews`, because `Fact_OrderItems` sits on the many side of its relationship to `Fact_Orders` and filters cannot travel back uphill.

Any measure based on `Fact_Orders` or `Fact_Reviews` is therefore blind to Seller and Category filters. Placed on a seller-level visual, such a measure returns the same global figure for every seller — a failure that renders correctly and looks plausible, which is what makes it dangerous.

Two classes of metric exist in this document as a result:

| Type | Base table | Responds to | Used on |
|---|---|---|---|
| Order-level (global) | `Fact_Orders` / `Fact_Reviews` | Date, Customer State | Page 5 (Delivery & Satisfaction) |
| Seller-aware (`TREATAS`) | `Fact_Orders` / `Fact_Reviews` via transferred order list | Date, Customer State, Seller, Category | Page 4 (Seller Performance) |

The `TREATAS` pattern is identical in every seller-aware measure: capture the order IDs visible in the current filter context from `Fact_OrderItems`, then apply that list as a filter on `Fact_Orders` or `Fact_Reviews`.

Bi-directional relationships would solve this without duplicate measures, but were rejected: they create ambiguous filter paths across two fact tables and can silently double-count. Explicit `TREATAS` keeps every measure deterministic and its intent visible in the code.

### 3.1 Total Sellers

- **Business definition:** Number of distinct sellers with at least one delivered order in the current filter context.
- **Owner:** Seller Management Lead

```dax
Total Sellers = 
CALCULATE(
    DISTINCTCOUNT('Fact_OrderItems'[seller_id]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Implementation note:** Counts `seller_id` from `Fact_OrderItems`, not from `Dim_Seller`. Counting the dimension would return the full seller list (3,095) regardless of any filter — including the delivered-status filter and every slicer — producing a card that never moves.

### 3.2 Seller Review Count **[helper]**

```dax
Seller Review Count = 
VAR SellerOrders = CALCULATETABLE(VALUES('Fact_OrderItems'[order_id]))
RETURN
CALCULATE(
    DISTINCTCOUNT('Fact_Reviews'[review_id]),
    TREATAS(SellerOrders, 'Fact_Reviews'[order_id])
)
```

### 3.3 Average Seller Review Score

- **Business definition:** Mean review score across reviewed orders containing the seller's items.
- **Owner:** Seller Management Lead

```dax
Avg Seller Review Score = 
VAR SellerOrders = CALCULATETABLE(VALUES('Fact_OrderItems'[order_id]))
RETURN
IF(
    [Seller Review Count] >= 20,
    CALCULATE(
        AVERAGE('Fact_Reviews'[review_score]),
        TREATAS(SellerOrders, 'Fact_Reviews'[order_id])
    )
)
```

- **Watch-outs:** Suppressed for sellers with fewer than 20 reviews — the average is not meaningful at low volume and would otherwise dominate any "worst sellers" ranking. The threshold is enforced in the measure, not by manual visual filtering, so it cannot be accidentally bypassed.

### 3.4 Avg Seller Delivery Days

- **Business definition:** Average calendar days from purchase to delivery, for orders containing the seller's items.
- **Owner:** Seller Management Lead

```dax
Avg Seller Delivery Days = 
VAR SellerOrders = CALCULATETABLE(VALUES('Fact_OrderItems'[order_id]))
RETURN
CALCULATE(
    AVERAGE('Fact_Orders'[delivery_days]),
    TREATAS(SellerOrders, 'Fact_Orders'[order_id]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Implementation note:** The seller-aware counterpart to `[Average Delivery Days]` (4.1). Plotted on the seller quality scatter, the global measure produced an identical value for every seller — a flat horizontal line that made the visual meaningless.

### 3.5 Seller Late Delivery Rate

- **Business definition:** Share of a seller's delivered orders that arrived after the estimated delivery date.
- **Owner:** Seller Management Lead

```dax
Seller Late Delivery Rate = 
VAR SellerOrders = CALCULATETABLE(VALUES('Fact_OrderItems'[order_id]))
VAR LateOrders = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        TREATAS(SellerOrders, 'Fact_Orders'[order_id]),
        'Fact_Orders'[order_status] = "delivered",
        'Fact_Orders'[is_late] = 1
    )
VAR DeliveredOrders = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        TREATAS(SellerOrders, 'Fact_Orders'[order_id]),
        'Fact_Orders'[order_status] = "delivered"
    )
RETURN DIVIDE(LateOrders, DeliveredOrders)
```

- **Implementation note:** Computed as its own ratio rather than `1 - [Seller On-Time Rate]`, because numerator and denominator each require the same `TREATAS` filter applied independently.

### 3.6 Seller Cancellation Rate

- **Business definition:** Share of all orders containing a seller's items that were cancelled or became unavailable.
- **Owner:** Seller Management Lead

```dax
Seller Cancellation Rate = 
VAR SellerOrders = CALCULATETABLE(VALUES('Fact_OrderItems'[order_id]))
VAR Cancelled = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        TREATAS(SellerOrders, 'Fact_Orders'[order_id]),
        'Fact_Orders'[order_status] IN {"canceled", "unavailable"}
    )
VAR AllOrders = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        TREATAS(SellerOrders, 'Fact_Orders'[order_id]),
        ALL('Fact_Orders'[order_status])
    )
RETURN DIVIDE(Cancelled, AllOrders)
```

- **Watch-outs:** As with the global Cancellation Rate (4.10), the denominator is all orders regardless of status, so this cannot be compared directly with any other rate in this document.

### 3.7 Top 10 Seller Revenue Share

- **Business definition:** Proportion of total revenue generated by the ten largest sellers.
- **Owner:** Seller Management Lead

```dax
Top 10 Seller Revenue Share = 
VAR Top10Sellers = 
    TOPN(10, ALL('Dim_Seller'[seller_id]), [Total Revenue], DESC)
RETURN
DIVIDE(
    CALCULATE([Total Revenue], Top10Sellers),
    CALCULATE([Total Revenue], ALL('Dim_Seller'))
)
```

- **Watch-outs:** A commercial risk indicator, not a performance indicator. High concentration means dependency on a small number of sellers. Date filters still apply, so this reads as "top 10 sellers in the selected period".

---

## 4. Delivery and satisfaction

**Scope note:** Most measures in this section are order-level and based on `Fact_Orders` or `Fact_Reviews`. Per the propagation rule in section 3, these respond to Date and Customer State filters but are blind to Category and Seller State. This is a deliberate analytical position, not a gap: an order can contain items from several categories and sellers, but it is delivered once and reviewed once, so attributing a whole-order outcome to a fraction of its contents is not well defined. The Category and Seller State slicers are removed from the Delivery & Satisfaction page so that a filter which would silently do nothing cannot be applied.

Two measures in this section are exceptions. `Reviewed Orders` (4.5) uses `TREATAS` and therefore stays filter-aware across Category and Seller State, and `Review Coverage` (4.6) inherits that behaviour because both its numerator and its denominator are filter-aware. This is required rather than optional: the denominator `[Total Orders]` is based on `Fact_OrderItems` and responds to every slicer, so an order-level numerator would produce a ratio over mismatched populations and coverage could exceed 100%. Order-level and filter-aware measures are distinguished per measure in the inventory table below.

### 4.1 Average Delivery Days

- **Business definition:** Average number of calendar days between purchase and delivery to the customer.
- **Grain:** Order
- **Owner:** Operations Manager

```dax
Average Delivery Days = 
CALCULATE(
    AVERAGE('Fact_Orders'[delivery_days]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Watch-outs:** Calendar days, not working days. `AVERAGE` ignores blanks, so orders without a delivery timestamp are naturally excluded. Regional averages are strongly affected by distance and should not be compared without that context.

### 4.2 On-Time Delivery Rate

- **Business definition:** The share of delivered orders that arrived on or before the estimated delivery date given to the customer.
- **Grain:** Order
- **Owner:** Operations Manager

```dax
On-Time Delivery Rate = 
VAR OnTimeOrders = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        'Fact_Orders'[order_status] = "delivered",
        'Fact_Orders'[is_late] = 0
    )
VAR DeliveredOrders = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        'Fact_Orders'[order_status] = "delivered"
    )
RETURN DIVIDE(OnTimeOrders, DeliveredOrders)
```

- **Watch-outs:** Measures performance against the estimate, not against a service standard. If estimates are generous, this rate can be high while actual delivery is slow. Always report alongside Average Delivery Days.

### 4.3 Late Delivery Rate

```dax
Late Delivery Rate = 1 - [On-Time Delivery Rate]
```

### 4.4 Average Review Score

- **Business definition:** Mean customer review score for delivered orders that received a review.
- **Grain:** Order

```dax
Average Review Score = 
CALCULATE(
    AVERAGE('Fact_Reviews'[review_score]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Watch-outs:** Coverage was validated in SQL against the warehouse and is effectively complete — 95,832 reviewed of 96,478 delivered orders (99.33%). The score can therefore be read as representative of the delivered-order population rather than a self-selected subset. Still report alongside Review Coverage so users can confirm coverage holds for whatever period or filter they have applied; if coverage drops materially below 99% under a filter, treat the score with more caution.

### 4.5 Reviewed Orders **[helper]**

```dax
Reviewed Orders = 
VAR RelevantOrders = CALCULATETABLE(VALUES('Fact_OrderItems'[order_id]))
RETURN
CALCULATE(
    DISTINCTCOUNT('Fact_Reviews'[order_id]),
    TREATAS(RelevantOrders, 'Fact_Reviews'[order_id]),
    'Fact_Orders'[order_status] = "delivered"
)
```

- **Implementation note:** Two corrections are combined here. First, the delivered filter must be stated explicitly — a filter applied inside `[Total Orders]` exists only during that measure's evaluation and does not carry across to sibling measures. Second, `TREATAS` is required because `Fact_Reviews` receives no filter from `Dim_Product` or `Dim_Seller` (see section 3's propagation note), while the denominator `[Total Orders]` is based on `Fact_OrderItems` and is filter-aware. Without it, numerator and denominator cover different populations under a Category filter and coverage can exceed 100%.

### 4.6 Review Coverage

- **Business definition:** The share of delivered orders that received a review.

```dax
Review Coverage = DIVIDE([Reviewed Orders], [Total Orders])
```

- **Validated baseline:** 95,832 reviewed of 96,478 delivered orders = 99.33%, confirmed by SQL against `olist_dw` and matching the Power BI measure exactly. Why coverage is this high is not established from the data available — only the coverage figure itself is verified.
- **Watch-outs:** This metric now serves as a check rather than a caveat — it exists to confirm coverage still holds under whatever filters a user has applied. A material drop below the 99% baseline signals either a data load problem or a filter combination with few reviewed orders, and should be investigated before the review score is quoted.

### 4.7 Avg Review Score On Time **[helper]**

```dax
Avg Review Score On Time = 
CALCULATE(
    AVERAGE('Fact_Reviews'[review_score]),
    'Fact_Orders'[order_status] = "delivered",
    'Fact_Orders'[is_late] = 0
)
```

### 4.8 Avg Review Score Late **[helper]**

```dax
Avg Review Score Late = 
CALCULATE(
    AVERAGE('Fact_Reviews'[review_score]),
    'Fact_Orders'[order_status] = "delivered",
    'Fact_Orders'[is_late] = 1
)
```

### 4.9 Late Delivery Review Gap

- **Business definition:** The difference in average review score between orders delivered on time and orders delivered late.
- **Owner:** Operations Manager

```dax
Late Delivery Review Gap = [Avg Review Score On Time] - [Avg Review Score Late]
```

- **Watch-outs:** This is an observed association, not proof of causation. Late deliveries and low scores may share a common cause such as seller reliability. State this whenever the metric is used to justify investment. Note, however, that with coverage at 99.33%, review-participation bias is unlikely to explain the gap materially: it holds across essentially the whole delivered-order population rather than a self-selected group of reviewers.

### 4.10 Cancellation Rate

- **Business definition:** The share of all orders placed that were cancelled or became unavailable.

```dax
Cancellation Rate = 
VAR CancelledOrders = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        'Fact_Orders'[order_status] IN {"canceled", "unavailable"}
    )
VAR AllOrders = 
    CALCULATE(
        DISTINCTCOUNT('Fact_Orders'[order_id]),
        ALL('Fact_Orders'[order_status])
    )
RETURN DIVIDE(CancelledOrders, AllOrders)
```

- **Watch-outs:** The only metric in this pack whose denominator is all orders rather than delivered orders. It cannot be compared directly with any other rate in this document.

---

## Measure inventory

35 measures total, of which 7 are helpers. This list matches the implemented `_Measures` table exactly.

| # | Measure | Section | Type | Filter scope |
|---|---|---|---|---|
| 1 | Total Revenue | Revenue | Base | All |
| 2 | Total Orders | Revenue | Base | All |
| 3 | Average Order Value | Revenue | Base | All |
| 4 | Units Sold | Revenue | Base | All |
| 5 | Revenue Previous Month | Revenue | Helper | All |
| 6 | Revenue MoM % Change | Revenue | Base | All |
| 7 | Revenue MoM % Change (Material) | Revenue | Base | All |
| 8 | Revenue Previous Year | Revenue | Helper | All |
| 9 | Revenue YoY % Change | Revenue | Base | All |
| 10 | Category Revenue Share | Revenue | Base | All |
| 11 | Freight Cost Ratio | Revenue | Base | All |
| 12 | Active Customers | Customer | Base | All |
| 13 | New Customers | Customer | Base | All |
| 14 | Returning Customers | Customer | Base | All |
| 15 | Repeat Customers | Customer | Helper | All |
| 16 | Repeat Purchase Rate | Customer | Base | All |
| 17 | Orders per Customer | Customer | Base | All |
| 18 | Revenue per Customer | Customer | Base | All |
| 19 | Total Sellers | Seller | Base | All |
| 20 | Seller Review Count | Seller | Helper | Seller-aware |
| 21 | Avg Seller Review Score | Seller | Base | Seller-aware |
| 22 | Avg Seller Delivery Days | Seller | Base | Seller-aware |
| 23 | Seller Late Delivery Rate | Seller | Base | Seller-aware |
| 24 | Seller Cancellation Rate | Seller | Base | Seller-aware |
| 25 | Top 10 Seller Revenue Share | Seller | Base | All |
| 26 | Average Delivery Days | Delivery | Base | Order-level |
| 27 | On-Time Delivery Rate | Delivery | Base | Order-level |
| 28 | Late Delivery Rate | Delivery | Base | Order-level |
| 29 | Average Review Score | Delivery | Base | Order-level |
| 30 | Reviewed Orders | Delivery | Helper | All |
| 31 | Review Coverage | Delivery | Base | All |
| 32 | Avg Review Score On Time | Delivery | Helper | Order-level |
| 33 | Avg Review Score Late | Delivery | Helper | Order-level |
| 34 | Late Delivery Review Gap | Delivery | Base | Order-level |
| 35 | Cancellation Rate | Delivery | Base | Order-level |

**Filter scope key:**
- **All** — responds to every slicer (Date, Customer State, Category, Seller State)
- **Seller-aware** — uses `TREATAS` to respond to Seller and Category as well as Date and Customer State
- **Order-level** — responds to Date and Customer State only; blind to Category and Seller State by design (see section 4 scope note)

## Measure formatting

Set format at measure level (Measure tools → Format), never per-visual:

| Measure type | Format |
|---|---|
| Revenue, AOV, Revenue per Customer | Currency, 0 dp (2 dp for AOV) |
| Order/customer/unit counts | Whole number, thousands separator |
| All `%` measures | Percentage, 1 dp |
| Average Delivery Days | Decimal, 1 dp |
| Review scores and gap | Decimal, 2 dp |

## Change control

| Version | Date | Change | Approved by |
|---|---|---|---|
| 1.0 | — | Initial definitions agreed | Head of Commercial |
| 2.0 | — | DAX updated to implemented model; customer metrics keyed on `customer_unique_id`; Repeat Purchase Rate reimplemented; helper measures documented; delivered-filter placement standardised | Head of Commercial |
| 2.1 | — | Reconciled against final implemented build: New Customers, Repeat Customers and Reviewed Orders DAX corrected; four seller measures added; filter-propagation rule and section 4 scope note documented; inventory corrected 30 → 35; `Revenue MoM % Change (Material)` added with 50,000 BRL judgement threshold; review-coverage assumption overturned by SQL validation (99.33%) | Head of Commercial |
