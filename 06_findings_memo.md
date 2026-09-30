# Commercial Findings Memo

**To:** Head of Commercial, Head of Marketing, Operations Manager, Seller Management Lead
**From:** Sayanth Rajani Divakaran, Data Analyst
**Subject:** NorthBay Retail — findings from the first commercial reporting cycle
**Version:** 1.0

> **Context note:** NorthBay Retail is a simulated business created to frame this analysis as a commercial reporting engagement. The underlying data is the Olist Brazilian E-Commerce public dataset (~100k orders, 2016–2018). All figures below are computed from that data and validated against the reporting pack; the business framing, stakeholders and recommendations are constructed by the author.

---

## Executive summary

The reporting pack is live and reconciled. Three findings warrant management attention.

**1. Retention is the weakest part of the commercial picture.** Roughly 3.0% of customers ever place a second order. With repeat purchase this rare, current revenue is heavily dependent on continued new-customer acquisition.

**2. At least one high-volume seller is performing materially below standard.** A seller with 114 reviews averages 2.33 stars against a marketplace average of 4.15. This is enough volume to rule out a small-sample artefact and warrants investigation.

**3. Late deliveries are associated with substantially lower review scores.** On-time orders average 4.08 stars; late orders average 2.48 — a gap of 1.60 points on a five-point scale. With review coverage at 99.33%, review-participation bias is unlikely to explain this gap materially.

Findings 1 and 3 are business-wide and structural. Finding 2 is specific and immediately actionable.

---

## Finding 1 — Customer retention is close to zero

### Evidence

- Lifetime repeat purchase rate: **3.0%** — 2,801 of 93,358 customers with a delivered order placed more than one (full history, validated in SQL and in the reporting pack)
- Measured on `customer_unique_id`, the person-level key. The source system issues a new order-level `customer_id` per order; using it would have reported a 0% repeat rate and hidden the issue entirely
- Order volume grew steadily across the reporting window while the repeat rate stayed broadly flat

### Interpretation

Almost every order comes from a customer making their first and only purchase. Commercially, this means current revenue is heavily dependent on continued new-customer acquisition: with repeat purchase this rare, the great majority of each period's orders must come from customers the business has not sold to before. A slowdown in new-customer volume would therefore be expected to show up in revenue quickly, since there is no substantial base of repeat purchasers to offset it.

Quantifying that dependency more precisely is not possible from the reporting pack. Acquisition cost, marketing spend and margin data are not available in source systems, so this analysis cannot assess whether acquisition is efficient, what a customer costs to win, or what lifetime value the business actually realises.

Two caveats on the number itself. First, repeat rate is highly sensitive to the time window selected: a one-month view will always show a low rate simply because there is little opportunity to repeat, so the 3.0% figure should be quoted as a lifetime measure and the window stated whenever it is used. Second, this analysis establishes that repeat purchase is rare; it does not establish why. Marketplace category mix, competitive alternatives and customer intent are all plausible contributors and none is measurable from the data available.

### Recommended action

1. **Adopt repeat purchase rate as a tracked KPI** with an explicit measurement window, rather than reporting it ad hoc. It is currently invisible in routine commercial reporting despite being the most material weakness identified.
2. **Run a diagnostic before designing an intervention.** Identify which categories, price points and regions show even marginally higher repeat rates — the reporting pack supports this segmentation today. A retention programme designed without knowing where repeat purchase already occurs is guesswork.
3. **Test post-purchase engagement on a limited segment with a control** before wider investment. Any intervention should be validated on a subset against a measured control group, so that a change in repeat purchase can be attributed to the intervention rather than to underlying trend.

---

## Finding 2 — A high-volume seller is underperforming on review score

### Evidence

- Seller `1ca7077d890b907f89be8c954a02686a` (state: SP)
- **114 reviews, average review score 2.33**
- Marketplace average review score: **4.15**
- The seller-level review measure suppresses any seller with fewer than 20 reviews, so this figure is not a low-volume artefact
- The seller quality view (review score against average delivery days, sized by revenue) shows this seller sitting well outside the main performance cluster

### Interpretation

A score of 2.33 across 114 reviews represents a sustained pattern of customer dissatisfaction, not a run of bad luck. The sample is large enough to be treated as reliable.

What the data does not tell us is the cause. Low scores could stem from product quality, listing accuracy, fulfilment reliability, customer communication, or a category where expectations are systematically harder to meet. These have very different remedies, and the reporting pack cannot distinguish between them.

The commercial exposure is twofold: direct dissatisfaction among customers who buy from this seller, and the reputational cost to the marketplace, since customers experience the purchase as a NorthBay transaction rather than a third-party one.

### Recommended action

1. **Investigate before acting.** Review the seller's listings, order history and review text to establish which failure mode is driving the score. Removal is not recommended on this evidence — a 2.33 average identifies a problem worth understanding, not a verdict.
2. **Apply the same 20-review threshold to build a standing watchlist.** This seller was found by sorting the underperformance table; the same view will surface others. A routine monthly check is more useful than a one-off finding.
3. **Set an intervention threshold with Seller Management.** Agree in advance what score, over what review volume, triggers a formal performance conversation. Acting case by case without a stated standard is difficult to defend to sellers.

---

## Finding 3 — Late delivery is associated with substantially lower review scores

### Evidence

Within the selected reporting period:

| Delivery outcome | Average review score |
|---|---|
| On time | **4.08** |
| Late | **2.48** |
| **Gap** | **1.60 points** |

- Late delivery is defined as arrival after the estimated delivery date communicated to the customer
- Overall on-time delivery rate: **92.0%**; average delivery time: **12.8 calendar days**
- **Review coverage: 99.33%** (95,832 reviewed of 96,478 delivered orders), validated independently in SQL and in the reporting pack

### Interpretation

The coverage figure is what makes this finding robust. With reviews on 99.33% of delivered orders, review-participation bias is unlikely to explain the 1.60-point gap materially — the usual objection to review-based analysis, that dissatisfied customers are disproportionately likely to leave feedback, has little room to operate when almost every order carries a review. The gap holds across the delivered-order population rather than a self-selected subset.

**This is an association, not proof of causation.** Late delivery has not been shown to cause lower scores. Both could plausibly share a common driver — a seller with unreliable fulfilment may also have weaker product quality or communication, producing late deliveries and low scores without one causing the other. Nothing in the available data separates these explanations.

That said, the effect size is large: a 1.60-point difference on a five-point scale, and the difference between an order customers rate positively and one they rate poorly.

The 8.0% late rate should be read carefully. It measures performance against the delivery estimate given to the customer, not against an absolute service standard. A generous estimate produces a high on-time rate while actual delivery remains slow, which is why the 12.8-day average is reported alongside it.

### Recommended action

1. **Treat late delivery rate as a customer satisfaction metric, not only an operational one.** It currently sits with Operations; the association with review scores makes it relevant to commercial and marketing reporting as well.
2. **Target the worst-performing regions first.** Late delivery rate varies materially by customer state and the reporting pack identifies the outliers. Improvement effort concentrated there will reach the most affected orders.
3. **Review how delivery estimates are set before optimising the on-time rate.** Because the metric is defined against the estimate, the rate can be improved by extending estimates rather than delivering faster. Any target on this metric should be paired with a target on actual delivery days to prevent that.
4. **Test the causal question if it is worth the cost.** If investment is contemplated, a controlled comparison — matching orders on seller, category and region, then comparing scores by delivery outcome — would narrow whether the effect is delivery-driven or seller-driven. The current pack cannot answer this.

---

## Limitations and caveats

These apply to every finding above and should be stated whenever the figures are quoted.

**No profitability view.** Cost-of-goods data is not available, so no finding addresses margin. Category and seller recommendations rest on revenue and volume only. A high-revenue category could be unprofitable and this analysis would not reveal it.

**Association, not causation.** The pack is descriptive and diagnostic. Where a relationship is reported — most importantly the delivery/review gap — it is an observed association. No causal claim is made or supported.

**Window sensitivity.** Repeat purchase rate, new-customer counts and returning-customer counts all depend heavily on the period selected. Any figure of this type must carry its window. The 3.0% repeat rate is a lifetime (full-history) figure.

**First-period distortion.** Every customer is "new" in the first month of the dataset, and the most recent month is incomplete. Both are excluded from trend visuals; conclusions drawn from those periods are unreliable.

**Order-level attribution.** Delivery and review metrics are order-level. An order may contain items from several categories and sellers but is delivered and reviewed once, so these metrics are deliberately not decomposed by category. The Category and Seller State filters are disabled on the delivery page to prevent a filter that would appear to work while doing nothing.

**Seller cause unknown.** Finding 2 identifies underperformance, not its reason. The recommendation is investigation for exactly this reason.

**Point-in-time figures.** All numbers reflect the dataset as loaded. Where a period is specified, changing it will change the figures — particularly the customer metrics.

---

## Next steps

| Action | Owner | Priority |
|---|---|---|
| Add repeat purchase rate to routine commercial reporting | Head of Commercial | Essential |
| Investigate seller `1ca7077d…` and establish a watchlist | Seller Management Lead | Essential |
| Agree seller intervention thresholds | Seller Management Lead | Essential |
| Review delivery estimate methodology | Operations Manager | Essential |
| Segment retention diagnostic by category and region | Head of Marketing | Optional |
| Design controlled test of the delivery/review relationship | Operations Manager | Optional |
