# Power BI Report Design Specification

**Project:** NorthBay Retail — Monthly Commercial Reporting Pack
**Version:** 2.0 — as built
**Purpose:** Page-by-page record of the Power BI report as implemented. Every visual traces back to a business question in the requirements note and a measure in `02_kpi_definitions_v2.1.md`.

> NorthBay Retail is a simulated business context. The data is the public Olist Brazilian E-Commerce dataset.

---

## Report at a glance

| Item | Value |
|---|---|
| Pages | 5 |
| Measures | 35, held in a dedicated `_Measures` table |
| Data source | PostgreSQL `olist_dw`, Import mode |
| Canvas | 16:9, 1280 × 720 |
| Default period | 1 January 2017 – 31 July 2018 |
| Screenshots | `images/01-executive-summary.png` to `images/05-delivery-satisfaction.png` |

---

## Design principles

1. **Custom theme, restrained palette.** One primary colour (deep teal) for the main metric, grey for secondary series and context. Colour carries meaning, not decoration.
2. **Every visual has a written title.** No auto-generated titles such as "Sum of price by year_month".
3. **No chart clutter.** Gridlines, data labels, borders and axis titles are removed where they add nothing.
4. **Formatting set on the measure, not the visual,** so each number looks the same everywhere it appears.
5. **The period is always visible.** Every page carries the slicer panel in the same position.
6. **Same layout grid on every page.** Header, slicers, KPI cards, primary trend, then detail.

---

## Shared elements

### Header

A teal band across the top: "NorthBay Retail — Commercial Performance", with the page name as a subtitle.

### Slicer panel

| Slicer | Field | Style | Pages |
|---|---|---|---|
| Period | `Dim_Date[date]` | Between (date range) | All five |
| Category | `Dim_Product[category]` | Dropdown | Pages 1–4 |
| Customer State | `Dim_Customer[most_recent_customer_state]` | Dropdown | All five |
| Seller State | `Dim_Seller[seller_state]` | Dropdown | Pages 1–4 |

Slicers are synced across the pages they appear on (View → Sync slicers), so a filter set on one page applies on the others.

**Page 5 exception.** The Category and Seller State slicers are removed from Delivery & Satisfaction, not merely hidden. Every delivery and review measure on that page is order-level and does not respond to category or seller filters (see the filter-propagation table in `03_data_model.md`). Leaving the slicers in place would let a user apply a filter that appears to work but changes nothing.

### Footer

On every page: *"Revenue = item price excl. freight, delivered orders only. Most recent partial month excluded from trend visuals. See KPI Definition Document for full metric definitions."*

### Trend visuals

Monthly trend visuals use `Dim_Date[year_month]` on the axis, sorted ascending, with the most recent partial month excluded by a visual-level filter.

---

## Page 1 — Executive Summary

**Audience:** Head of Commercial. **Answers:** how are we performing, and what changed? **Business questions:** 1, 2, 3.

| Visual | Fields | Notes |
|---|---|---|
| KPI cards (5) | `Total Revenue`, `Total Orders`, `Average Order Value`, `Active Customers`, `On-Time Delivery Rate` | |
| MoM card | `Revenue MoM % Change` | Small labelled card under Total Revenue |
| Revenue and Order Volume by month | Line and clustered column. Axis `year_month`; columns `Total Revenue`; line `Total Orders` on secondary axis | Shows whether growth comes from more orders or larger baskets |
| Revenue by Category – Top 8 | Horizontal bar. `Dim_Product[category]` by `Total Revenue`; Top N filter = 8 | Bars rather than a donut: length reads more accurately than angle |
| Category performance vs prior month | Matrix. Rows `category`; values `Total Revenue`, `Revenue MoM % Change (Material)`, `Category Revenue Share` | Sorted by MoM % descending; data bars on revenue |

**Small-base handling on the matrix.** Sorted by raw MoM %, the top rows were categories with around 1,000 BRL of revenue showing changes above +250%. Two fixes were considered:

- A visual-level filter of Total Revenue > 50,000 was **rejected**. It removes rows, so the matrix total fell to 11.72M / 95% and no longer matched the 12.34M Total Revenue card.
- `Revenue MoM % Change (Material)` was **adopted**. It returns blank for categories below 50,000 BRL, keeps every row, and leaves the total at 12,342,450.49 / 100%. Blank values sort to the bottom, so the largest movers among material categories appear first. The 50,000 BRL threshold is a judgement call, not a derived figure (KPI document 1.7).

---

## Page 2 — Category & Product Performance

**Audience:** Category Managers. **Business questions:** 2, 3.

| Visual | Fields | Notes |
|---|---|---|
| KPI cards (4) | `Total Revenue`, `Units Sold`, `Average Order Value`, `Freight Cost Ratio` | |
| Category Revenue trend – Top 5 | Line chart. Axis `year_month`; values `Total Revenue`; legend `category`; Top N filter = 5 | More than five lines becomes unreadable |
| Category Detail | Matrix. Rows `category`; values `Total Revenue`, `Units Sold`, `Total Orders`, `Average Order Value`, `Category Revenue Share` | Sorted by revenue; data bars on revenue; font size 8–9 so several rows are visible |
| Freight Cost Ratio v Revenue by Category | Scatter. X `Total Revenue`; Y `Freight Cost Ratio`; details `category` | Shows categories whose delivery cost is high relative to revenue |

---

## Page 3 — Customer Behaviour

**Audience:** Head of Marketing. **Business questions:** 4, 5, 6.

| Visual | Fields | Notes |
|---|---|---|
| KPI cards (5) | `Active Customers`, `New Customers`, `Returning Customers`, `Repeat Purchase Rate`, `Revenue per Customer` | All counted on `customer_unique_id` |
| Note under the cards | "Lifetime repeat purchase rate is 3.0%." | The cards reflect the selected period; this note gives the full-history figure (2,801 of 93,358 customers) |
| Customer volume and repeat purchase rate by month | Line and clustered column. Axis `year_month`; columns `Active Customers`; line `Repeat Purchase Rate` on secondary axis | |
| Revenue by Customer state – Top 10 | Horizontal bar. `most_recent_customer_state` by `Total Revenue`; Top N = 10 | A bar chart rather than a map: map visuals handle Brazilian state codes unreliably |
| Region detail | Table. `most_recent_customer_state`, `Total Revenue`, `Active Customers`, `Revenue per Customer`, `Average Order Value` | Sorted by revenue |

**Design change during the build.** The trend visual was first a stacked column of New vs Returning Customers. With repeat purchase this rare, the Returning series was too small to see, so the chart showed one series and hid the point. It was replaced with active customer volume plus the repeat purchase rate on its own axis, which shows volume growing while retention stays low. New and Returning are shown for the selected period as cards.

---

## Page 4 — Seller Performance

**Audience:** Seller Management Lead. **Business questions:** 7, 8, 9 (by seller).

| Visual | Fields | Notes |
|---|---|---|
| KPI cards (4) | `Total Sellers`, `Top 10 Seller Revenue Share`, `Average Review Score`, `Seller Cancellation Rate` | `Total Sellers` counts sellers on `Fact_OrderItems`, so it responds to filters. `Seller Cancellation Rate` uses the seller-aware version, not the marketplace-wide rate |
| Top 15 Seller By revenue | Horizontal bar. `Dim_Seller[seller_id]` by `Total Revenue`; Top N = 15 | Seller IDs are anonymised hashes in the source; no names exist |
| Seller quality: review score vs delivery speed | Scatter. X `Avg Seller Review Score` (axis fixed 1–5); Y `Avg Seller Delivery Days`; size `Total Revenue`; details `seller_id` | See note below |
| Worst-performing sellers — 20+ reviews only | Table. `seller_id`, `seller_state`, `Total Revenue`, `Seller Review Count`, `Avg Seller Review Score`, `Seller Late Delivery Rate` | Sorted by review score ascending |

**Seller-aware measures.** The Y-axis uses `Avg Seller Delivery Days`, not `Average Delivery Days`. The global measure is based on `Fact_Orders`, which seller filters do not reach, so every seller received the same marketplace average and the scatter collapsed into a flat line. The seller versions use `TREATAS` to apply each seller's orders to `Fact_Orders` and `Fact_Reviews` (KPI document section 3).

**Reading the scatter.** Low review score and slow delivery sit in the **top-left**. Large bubbles there are high-revenue sellers performing poorly on both.

**The table total is deliberately a subset.** Only sellers with at least 20 reviews are shown, matching the threshold built into `Avg Seller Review Score`. The table's total row therefore covers only those sellers and does not equal the page's Total Revenue.

---

## Page 5 — Delivery & Satisfaction

**Audience:** Operations Manager. **Business questions:** 9 (by month and region), 10, 11. **Slicers:** Period and Customer State only.

| Visual | Fields | Notes |
|---|---|---|
| KPI cards (5) | `Average Delivery Days`, `On-Time Delivery Rate`, `Late Delivery Rate`, `Average Review Score`, `Review Coverage` | Score and coverage sit side by side, so the score is always read with its coverage (99.33% full history) |
| Delivery speed and on-time performance by month | Line and clustered column. Axis `year_month`; columns `Average Delivery Days`; line `On-Time Delivery Rate` on secondary axis | Both are shown because on-time rate is measured against the estimate: a generous estimate can give a high on-time rate alongside slow delivery |
| Late delivery rate by Customer state | Horizontal bar. `most_recent_customer_state` by `Late Delivery Rate`, sorted descending | |
| Review score: on-time vs late delivery | Three cards: `Avg Review Score On Time`, `Avg Review Score Late`, `Late Delivery Review Gap` | Cards rather than a two-bar chart; the gap is the number that matters |
| Caveat text | "Observed association, not causation — late delivery and low scores may share a common cause such as seller reliability." | Required wherever the gap is shown |

---

## Validated figures in the screenshots (1 Jan 2017 – 31 Jul 2018)

| Page | Figure | Value |
|---|---|---|
| Executive Summary | Total Revenue / Total Orders / AOV | 12.34M / 90K / 137.35 |
| Executive Summary | Revenue MoM % Change (period total) | 7.6% |
| Category & Product | Units Sold / Freight Cost Ratio | 103K / 16.6% |
| Customer Behaviour | Active customers / Repeat Purchase Rate | 87K / 3.0% |
| Seller Performance | Top 10 Seller Revenue Share / Seller Cancellation Rate | 13.6% / 0.5% |
| Delivery & Satisfaction | Average Delivery Days / On-Time Delivery Rate / Average Review Score | 12.8 / 92.0% / 4.15 |
| Delivery & Satisfaction | On-time score / late score / gap | 4.08 / 2.48 / 1.60 |

The same figures can be reproduced in SQL with `sql_03_business_queries.sql`.

---

## Not built

A sixth page summarising data quality and metric definitions was considered and not built. That content lives in `04_data_quality_log.md` and `02_kpi_definitions_v2.1.md`.

---

## Final checks

- [x] Every visual has a written title
- [x] Measures formatted at measure level
- [x] Slicers synced across Pages 1–4; Page 5 carries Period and Customer State only
- [x] Trend visuals exclude the most recent partial month
- [x] Matrix and card totals reconcile on the Executive Summary
- [x] Screenshots saved to `images/` for the README

## Change control

| Version | Change |
|---|---|
| 1.0 | Initial specification before build |
| 2.0 | Rewritten as built: Page 5 slicer exception; `Revenue MoM % Change (Material)` on Page 1; Page 2 detail matrix columns; Page 3 trend redesigned; Page 4 seller-aware measures, quadrant reading corrected to top-left, table total explained; Page 5 review-score cards and caveat; planned Page 6 marked not built; validated figures recorded |
