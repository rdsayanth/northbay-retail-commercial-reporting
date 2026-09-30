# Commercial & Customer Performance Reporting — Requirements Note

**Project:** NorthBay Retail — Monthly Commercial Reporting Pack
**Prepared by:** Sayanth Rajani Divakaran (Data Analyst)
**Version:** 1.1
**Status:** Delivered — see section 11 for status against each requirement

> **Context:** NorthBay Retail is a simulated marketplace business created to frame this project as a commercial reporting engagement. The underlying data is the public [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (approximately 100,000 orders, 2016–2018). The stakeholders, background, requirements and recommendations below are constructed by the author to reflect how this work would be scoped in a commercial environment. NorthBay Retail is not a real company and not an employer.

---

## 1. Background

NorthBay Retail operates an online marketplace where third-party sellers list products and NorthBay handles order routing, payment and delivery coordination. The business has grown to a point where the existing reporting process no longer supports decision-making:

- The monthly commercial pack is assembled manually in Excel from several separate system exports.
- Preparation takes approximately two working days each month and is owned by a single person.
- Metrics are recalculated by hand each cycle, so definitions drift between months and between teams. Marketing and Commercial currently report different figures for "active customers".
- Delivery performance is reviewed only when a complaint escalates, rather than monitored as a standing metric.

The Head of Commercial has asked for a repeatable reporting solution that replaces the manual pack, standardises metric definitions, and makes performance visible without an analyst assembling it by hand.

## 2. Stakeholders

| Stakeholder | Role | Primary interest |
|---|---|---|
| Head of Commercial | Requestor / sign-off | Revenue trend, category revenue mix, order value |
| Category Managers | Day-to-day users | Product and category-level detail, top and bottom movers |
| Head of Marketing | Consumer | New vs repeat customers, retention, order value |
| Operations Manager | Consumer | Delivery lead time, on-time performance, late-delivery hotspots |
| Seller Management Lead | Consumer | Seller volume, cancellation and review performance |

## 3. Business questions in scope

The reporting pack must answer the following without further ad-hoc analysis:

**Revenue and commercial performance**
1. How is revenue trending month on month and year on year?
2. Which product categories drive revenue, and how is that mix changing?
3. What is average order value, and is it moving?

**Customer behaviour**
4. How many customers are active each month, and how many are new vs returning?
5. What proportion of customers place more than one order?
6. Which states or regions contribute most revenue, and where is growth coming from?

**Seller performance**
7. Which sellers account for the largest share of orders and revenue?
8. Which sellers are underperforming on delivery time or review score?

**Delivery and satisfaction**
9. What is average delivery lead time, and how does it vary by region and seller?
10. What share of orders are delivered after the estimated delivery date?
11. Does late delivery correlate with lower review scores, and what is the size of that effect?

## 4. Out of scope

- **Profit and margin reporting** — cost-of-goods data is not available in the source.
- **Acquisition cost and customer lifetime value** — marketing spend and acquisition cost are not available.
- **Marketing channel attribution and campaign performance.**
- **Forecasting and predictive modelling.** The pack is descriptive and diagnostic only.
- **Real-time or intra-day refresh.** Monthly cadence is sufficient for the decisions being supported.
- **Individual customer-level views.** Reporting is aggregated; no customer is identifiable in the output.

## 5. Deliverables

| # | Deliverable | File | Status |
|---|---|---|---|
| 1 | Requirements note | `01_requirements_note.md` | Delivered |
| 2 | KPI definition document — agreed calculation logic for all 35 measures | `02_kpi_definitions_v2.1.md` | Delivered |
| 3 | Dimensional data model (star schema) | `03_data_model.md` | Delivered |
| 4 | Data quality log — issues found, treatment rules, validation results | `04_data_quality_log.md` | Delivered |
| 5 | Power BI report specification — five pages as built | `05_powerbi_report_design.md` | Delivered |
| 6 | Commercial findings memo — findings and recommendations | `06_findings_memo.md` | Delivered |
| 7 | SQL transformation layer — raw → staging → warehouse | `sql_01_staging.sql`, `sql_02_dimensions_and_facts_postgres.sql` | Delivered |
| 8 | SQL business queries and reconciliation against the report | `sql_03_business_queries.sql` | Delivered |
| 9 | Power BI report — five pages | Screenshots in `images/` | Delivered |
| 10 | Monthly refresh runbook | — | Deferred; rebuild and validation steps are summarised in the README |

## 6. Data sources

The Olist dataset is supplied as nine CSV files. They are loaded unchanged into the PostgreSQL schema `olist_raw`.

| Source file | Contents | Grain | Used in warehouse |
|---|---|---|---|
| Orders | Order header: status, purchase, approval, delivery and estimated delivery timestamps | One row per order | Yes → `Fact_Orders` |
| Order items | Line items: product, seller, price, freight | One row per order line | Yes → `Fact_OrderItems` |
| Customers | `customer_id`, `customer_unique_id`, city, state | One row per `customer_id` — which is **one row per order**, not per person | Yes → `Dim_Customer` |
| Products | Product, category (Portuguese), dimensions | One row per product | Yes → `Dim_Product` |
| Category name translation | Portuguese → English category names | One row per category | Yes, in staging |
| Sellers | Seller, city, state | One row per seller | Yes → `Dim_Seller` |
| Reviews | Review score and dates by order | One row per review | Yes → `Fact_Reviews` |
| Order payments | Payment type and instalments | One row per payment | No — not needed for any in-scope question |
| Geolocation | Postcode coordinates | One row per postcode point | No — regional reporting uses state |

Monetary values are in Brazilian reais (BRL), as supplied.

## 7. Requirements

**Functional**
- All KPIs are calculated from the definitions in the KPI definition document. No metric may be defined only inside a visual.
- Month-on-month and year-on-year comparison is supported through a dedicated, generated date dimension marked as the Power BI date table.
- Users can filter by period, category, customer state and seller state, with filter state visible on the page. **Exception:** the Delivery & Satisfaction page carries only the period and customer state slicers. Its measures are order-level and do not respond to category or seller filters, so those slicers are removed rather than left to appear functional while doing nothing.
- The report opens on the period 1 January 2017 – 31 July 2018. This excludes the sparse 2016 months at the start of the dataset and the incomplete months at the end.
- Month-on-month percentages on the category table are suppressed for categories below 50,000 BRL of revenue in the period, so that small bases do not dominate the ranking. The category rows are kept, so totals still reconcile.

**Non-functional (targets)**
- A new set of exports refreshes the pack by rerunning the SQL scripts and refreshing Power BI, without editing queries or measures.
- Every metric shown can be traced back to a documented transformation step and a documented measure.
- Warehouse totals reconcile with the report. Reconciliation queries are provided in `sql_03_business_queries.sql`.

## 8. Assumptions

- Only orders with status `delivered` count toward revenue. Cancelled and unavailable orders are reported separately as a cancellation rate, not netted off revenue.
- Revenue is item price excluding freight. Freight is reported separately as a cost ratio.
- Order date is the purchase date, not the approval or delivery date.
- Products with no category are grouped as `Uncategorised` rather than dropped, so that revenue totals reconcile.
- **Customers are identified by `customer_unique_id`.** In the source, `customer_id` is issued per order, so the same physical person has a different `customer_id` on every order. Counting on `customer_id` would make every customer look new and set the repeat purchase rate to zero. See Data Quality Log entry 3.0.
- A customer's city and state are taken from their most recent order. See Data Quality Log entry 3.0.1.

## 9. Known limitations

- Without cost data, no profitability view is possible. Category findings are based on revenue and volume only.
- Delivery estimates are generated by the source system; their accuracy is not independently verified. On-time rate measures performance against the estimate, not against a service standard.
- Delivery and review metrics are order-level. An order may contain items from several categories and sellers but is delivered and reviewed once, so these metrics are not decomposed by category. Seller-level delivery and review figures are shown on the Seller Performance page using the orders that contain each seller's items.
- Repeat purchase rate is sensitive to the period selected. The lifetime (full-history) rate is 3.0%: 2,801 of 93,358 customers with a delivered order placed more than one.
- The dataset covers a fixed historical period. The earliest and latest months are sparse or incomplete and are excluded from trend conclusions.

**Assumption tested and corrected during the build:** version 1.0 of this note stated that reviews were voluntary and covered only a subset of orders. SQL validation showed review coverage of 99.33% (95,832 reviewed of 96,478 delivered orders), so review-based metrics are not limited to a small self-selected sample. See Data Quality Log entry 6.2.

## 10. Success criteria

1. Every business question in section 3 can be answered from the report without ad-hoc analysis.
2. Metric definitions are documented and agreed, and the "active customers" discrepancy between Commercial and Marketing is resolved to a single figure.
3. A new month of data can be refreshed and published in under 30 minutes, down from two working days.
4. The findings memo has been reviewed by the Head of Commercial with agreed actions.

## 11. Status against requirements

### Business questions

| # | Question | Status | Where answered |
|---|---|---|---|
| 1 | Revenue trend, MoM and YoY | **Partly met.** Monthly trend and MoM % are shown. The YoY measures exist in the model but are not displayed on any page. | Executive Summary |
| 2 | Category revenue and mix | Met | Executive Summary; Category & Product |
| 3 | Average order value | Met | Executive Summary; Category & Product |
| 4 | Active, new and returning customers | **Mostly met.** Active customers are charted monthly; new and returning are shown for the selected period as cards rather than charted by month. | Customer Behaviour |
| 5 | Share of customers ordering more than once | Met — 3.0% lifetime | Customer Behaviour |
| 6 | Revenue by state; where growth comes from | **Partly met.** Revenue by state is shown; regional growth over time is not charted. | Customer Behaviour |
| 7 | Largest sellers by revenue and orders | Met | Seller Performance |
| 8 | Underperforming sellers | Met — 20+ reviews only | Seller Performance |
| 9 | Delivery lead time by region and seller | **Mostly met.** Average delivery days are shown by month and by seller; by region, the late delivery rate is shown rather than average days. | Delivery & Satisfaction; Seller Performance |
| 10 | Share of orders delivered late | Met — 8.0% in the default period | Delivery & Satisfaction |
| 11 | Late delivery and review scores | Met — 1.60-point gap, reported as an association | Delivery & Satisfaction |

### Success criteria

| # | Criterion | Status |
|---|---|---|
| 1 | All business questions answerable | Mostly met — gaps noted above |
| 2 | Definitions agreed; active customers resolved | Met — active customers are distinct `customer_unique_id` values with at least one delivered order |
| 3 | Refresh in under 30 minutes | Not tested — the source dataset is static, so no monthly refresh has been run |
| 4 | Memo reviewed by Head of Commercial | Memo produced; stakeholder review is part of the simulated context |

## Change control

| Version | Change |
|---|---|
| 1.0 | Initial requirements for build |
| 1.1 | Updated to the delivered state: Olist dataset named; customer key corrected to `customer_unique_id`; source files listed with usage; Delivery & Satisfaction slicer exception, default period and materiality threshold recorded; review-coverage assumption corrected (99.33%); deliverables mapped to repository files; status against every business question and success criterion added |
