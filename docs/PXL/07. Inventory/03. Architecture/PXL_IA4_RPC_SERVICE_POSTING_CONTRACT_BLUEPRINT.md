# PXL IA-4 Inventory RPC, Service, and Posting Contract Blueprint

**Status:** IA-4 planning baseline
**Authority:** Service contract derived from frozen IA-3 architecture
**Last Reviewed:** 2026-07-26
**Implementation Status:** Design only; no RPC, code, SQL, or Posting change is authorized

## 1. Service boundaries

Public/governed workflow services may admit commands and return plans/results. Internal
Inventory services calculate and persist Inventory-owned events and method state.
Only the frozen Posting Engine persists journals, using the six sanctioned Kernel
functions. Reporting services are read-only.

All mutation services require:

- authenticated company membership and operation permission;
- a source version and caller idempotency key;
- explicit source header and line identities;
- explicit accounting profile, scope, method, precision/currency, ownership, period,
  and dimension resolution;
- stable lock ordering and one database transaction;
- rollback of Inventory and GL together;
- deterministic replay of a successful response; and
- failure before any visible partial state.

Retries with the same command and unchanged source return the original occurrence.
Retries with a reused key and changed content fail. Serialization/deadlock failures may
be retried with the same key; validation, policy, period, insufficiency, and unsupported
source failures are terminal until the source is corrected.

## 2. Current RPC/service census and target disposition

| Workflow | Current RPC/service | Census | Target service contract | Owner / caller | Dependencies | Idempotency and transaction boundary | Failure and retry |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Purchase Order | `fn_save_purchase_order`; UI governed save | Reusable, incomplete master facts | Save/approve PO with ownership terms and acquisition-policy evidence | Purchasing / Purchase UI | Vendor, item/UOM, branch, policy | Header version + command key; document transaction only | Validation terminal; safe same-key retry |
| Receiving Report | `fn_save_receiving_report`, `fn_confirm_receiving_report` | Legacy confirmation | Save inspection; confirm line-grained custody/ownership occurrence | Purchasing orchestrates / RR UI | PO lines, warehouse, ownership, method receipt service | One RR version/key; confirmation includes Inventory and optional Posting atomically | Entire confirmation rolls back; same-key retry |
| Goods Receipt | `fn_receive_inventory(jsonb)` | Legacy and externally exposed; replacement required | Admit/calculate/commit governed Goods Receipt for explicit source class | Inventory / RR, shipment, opening, return, approved adjustment orchestration only | Scope, method, cost hierarchy, UOM, source line, PE when owned | Unique source occurrence; Inventory + PE one transaction | No partial projection; policy/source failure terminal |
| Vendor Bill | `fn_save_vendor_bill`, approve/post/void writers | Reusable AP shell, incorrect Inventory boundary | Post bill occurrence, create line matches, clear GRNI/GINR, request Inventory correction where applicable | Purchasing/AP / Vendor Bill UI | Tax, COA, purchase match, receipt occurrences | Existing source lock extended to match rows; AP/Tax/match/Inventory correction/PE atomic | Match race retries; invalid overmatch terminal |
| Payment | Existing payment posting services | Reusable unchanged | Existing AP settlement contract | Treasury/AP | AP, cash, PE | Existing source lock | Existing behavior |
| Cash Purchase | `fn_save_cash_purchase`, `fn_post_cash_purchase` | Partial | Composite paid bill + owned receipt occurrence | Purchasing/AP orchestrates | Inventory receipt, Tax, COA, Treasury, PE | One source occurrence; all effects atomic | Any failure rolls back all; same-key retry |
| Vendor Credit | `fn_save_vendor_credit`, `fn_post_vendor_credit`, application services | Reusable financial shell | Post price-only credit and linked correction request, or link to physical return | AP/Tax | Purchase match, Inventory correction/return | Credit and correction occurrence share source key and transaction when accounting together | No unlabeled credit; correction failure rolls back post |
| Purchase Return | save/ship/`fn_complete_purchase_return` | Legacy financial-only completion | Approve/dispatch/complete physical return, remove method carrying cost, then clear GRNI or link credit | Inventory + Purchasing/AP / Returns UI | Identity/availability, method state, purchase match, Tax/AP, PE | Line/source occurrence and locks; physical/financial plan atomic when simultaneous | Insufficient/identity/match failures terminal; contention retry |
| Sales Order | UI/source services | Partial | Reserve/release/consume availability without owned/value/GL effect | Sales requests; Inventory owns reservation | Item/location availability | Source-line version and key; reservation transaction | Contention retry; over-reserve terminal |
| Delivery / Sales recognition | Direct PostgREST document writes; no governed posting service | Missing/legacy | Save/confirm delivery; source-locked control-transfer recognition combines Sales and Inventory plans | Sales orchestrates / Delivery UI | Sales policy, Tax, Inventory issue, COA, PE | One delivery-line recognition occurrence; Sales + Inventory + PE atomic | No revenue without COGS or reverse; entire occurrence retryable |
| Sales Invoice | `fn_save_sales_invoice`, approve/post/void | Reusable billing shell, current cost timing incorrect | Bill/reclassify linked recognized delivery; simultaneous delivery/invoice supported by same occurrence | Sales/AR | Recognition occurrence, Tax, PE | Existing source lock plus recognition link | Duplicate billing link terminal; contention retry |
| Sales Return | No governed Inventory return service | Missing | Accept/inspect return; restore exact linked corrected issue cost; classify blocked/available | Inventory + Sales / Return UI | Original issue allocations, identity, method, Credit Memo link | One return acceptance occurrence; optional simultaneous financial credit atomic | Missing ancestry/identity terminal; same-key retry |
| Credit Memo | Existing save/post services | Reusable financial shell | Post financial credit linked to return or explicit price-only event | Sales/AR/Tax | Sales return occurrence, invoice | Existing source lock plus typed relationship | Physical claim without link rejected |
| Stock Adjustment | `fn_post_stock_adjustment` wrapper/internal implementation | Reusable shell, legacy costing | Calculate/preview/post approved quantity adjustment with method-specific evidence | Inventory / Adjustment UI | Method state, reason/account, ownership | Existing source lock + event key; Inventory + PE atomic | Stale preview recalculates; missing evidence terminal |
| Physical Count | `fn_post_physical_count` wrapper/internal implementation | Reusable shell, incomplete positive policy | Freeze snapshot, approve variance, then invoke adjustment occurrence | Inventory / Count UI | Snapshot, identity, measured cost, ownership | Snapshot/version and approval key; adjustment + PE atomic | Specific ID without evidence quarantined; no zero-cost fallback |
| Goods Issue | `fn_post_goods_issue` wrapper/internal implementation | Reusable shell, legacy costing | Calculate/preview/post governed non-sales issue | Inventory / Issue UI or certified source engine | Method state, destination role, dimensions, PE | Existing source lock + event key; atomic | Unsupported WIP/source fails closed |
| Stock Transfer | `fn_post_stock_transfer` wrapper/internal implementation | Reusable shell, incorrect layer semantics | Approve, dispatch, receive, reverse paired transfer events | Inventory / Transfer UI | Source availability, target scope, transit, identity, PE if reclass | Transfer key; scope locks sorted; dispatch/receipt each idempotent and linked | Partial transport explicit; no silent half-post |
| Opening Conversion | No governed service | Missing | Create/validate/post/certify one complete opening batch | Conversion + Inventory / controlled setup UI | Policy/scope/method state, full Trial Balance, PE | Batch version/key; posting atomic; certification only at zero suspense | Any variance blocks; no auto-balance or retry with changed content |
| Landed Cost | None | Missing | Capture/approve source, calculate allocation, preview, post correction | Purchasing/AP + Inventory | Receipt sources, allocation policy, method replay, PE | One cost-source occurrence; allocations + correction + PE atomic | Missing basis or unmatched amount terminal |
| Cost Correction | None | Missing | Classify, replay scope, produce destination bridge, approve/post | Inventory + Period | Source evidence, replay, periods, PE | Correction version/key; locks scope and source; append-only | Closed-period classification mandatory; no source mutation |
| NRV | None | Missing | Assess/approve/write down/reverse allowance | Inventory + Accounting Policy | Evidence, scope, prior allowance, PE | Assessment/version key; adjustment + PE atomic | Above-cost reversal rejected |
| Negative deficit | Policy resolver only | Missing lifecycle | Admit provisional FIFO/WAC issue, settle on receipt, block close while open | Inventory | Policy, provisional cost source, method state, Period | Deficit identity tied to issue; receipt settlement atomic | Specific ID and missing policy reject |
| Consignment | Warehouse type only | Legacy | Custody receipt/transfer and explicit ownership conversion | Inventory + Purchasing/Sales | Terms/evidence, identity/location, PE only at ownership/control | Source occurrence; simultaneous acquisition/issue atomic if consumed | Unknown ownership fails closed |
| Inventory reversal | Workflow-specific | Partial | Reverse source occurrence by exact event/method allocation ancestry | Inventory | Original event/allocations, Period, PE reversal | Unique reversal key; Inventory restoration + journal reversal atomic | Duplicate returns original reversal; closed-period policy enforced |
| Inventory preview | Sales and source-specific preview functions | Legacy/incomplete | Pure calculation over locked versioned inputs; no persistence | Inventory, exposed through workflow preview | Same validators/resolvers/method calculator as actual | Preview fingerprint includes input versions; actual re-locks/recomputes | Stale fingerprint reported, not force-posted |
| Inventory reports/reconciliation | Frontend direct selects | Legacy | Named read-only report services with cut-off/watermark/fingerprint | Reporting / pages and certification | Authoritative events/state/GL independent sources | Read-only repeatable snapshot | Stale/incomplete projections disclosed or rejected |

## 3. Internal service set

These are logical service responsibilities, not proposed public SQL function names:

| Internal service | Responsibility | Callers | Must never do |
| --- | --- | --- | --- |
| Inventory admission | Permission, lifecycle, source class, ownership, UOM, period, policy, scope, method, identity, availability validation | Governed workflow orchestrators | Journal creation or heuristic defaulting |
| Event identity/order | Allocate source occurrence and deterministic event order | Admission/commit | Change effective order after commit |
| Method calculator — FIFO | Receipt layer, queue consumption, returns, transfer order, replay results | Inventory workflows | Use WMS picking as valuation order |
| Method calculator — WAC | Pool transitions, receipt evidence, exact issue/return/transfer/replay values | Inventory workflows | Consume WAC receipt records |
| Method calculator — Specific ID | Identity eligibility, direct value, location/status lifecycle | Inventory workflows | Issue absent identity or allow negative |
| UOM/precision allocator | Normalize base quantity, authoritative amounts, stable residual allocation | All calculators | Binary floating point or rate-based reconstruction |
| Projection rebuilder | Rebuild stock, reservation, method-current, and report projections from immutable facts | Commit/replay/admin certification | Become source of truth or post adjustments |
| Purchase-match adapter | Accept Purchasing-owned matches and translate approved price/cost delta to correction request | Vendor Bill/receipt/return orchestration | Recalculate AP/tax or own match ledger |
| Correction replay | Recompute affected method state and build full destination bridge | Cost correction, landed cost, rebate, backdate | Update old events/journals |
| Posting-plan adapter | Translate Inventory outputs to certified account roles, line roles, dimensions, provenance, and ordered plan | Mutation orchestrators | Resolve cost, tax, or mutate journal tables directly |
| Reconciliation engine | Read independent sources and record first failing equality | Reports/close/certification | Create or propose balancing journal |

## 4. Common Posting payload

Every accounting Inventory occurrence supplies the frozen Posting Engine with:

- company, branch/dimension context, source type/header/line, source occurrence and
  idempotency identity;
- posting/effective date and open-period evidence;
- accounting profile, cost-formula policy, method, valuation scope, precision/currency,
  and replay/correction versions;
- functional-currency GL-basis amounts already calculated by Inventory;
- account roles for COA resolution, never arbitrary Inventory/COGS account IDs from the
  encoder;
- ordered logical lines containing line role, debit or credit amount, dimensions,
  inventory event/value/allocation provenance, tax output reference where applicable,
  and audit narrative;
- reversal/correction ancestry; and
- a deterministic Posting Plan fingerprint shared with preview.

The Posting Engine returns the existing journal identity, number, ordered line
identities, posting/audit identity, and completion status. It never returns a cost
decision to Inventory.

## 5. Transaction Posting contracts

`Conditional` means no company-level journal is created when accounts and GL dimensions
do not change; the Inventory event still exists.

| Inventory transaction | Inventory inputs | Inventory outputs | Validation requirements | Frozen PE entry | Expected journal contract |
| --- | --- | --- | --- | --- | --- |
| Owned Goods Receipt before bill | Accepted source line, control evidence/date, base quantity, approved provisional acquisition components, tax recoverability input, scope/method/dimensions | Receipt event, method-state increase, stock projection, GRNI occurrence | PO/shipment/item hierarchy, ownership, UOM, period, location, identity | Existing source-locked posting adapter and six Kernel functions | Dr Inventory (or Inventory in Transit) / Cr GRNI; exact extended amount; tax only from Tax boundary |
| Bill before control | AP bill occurrence and Purchase Match status; no Inventory quantity | No Inventory event until control; GINR match evidence consumed by reports | Explicit absence of control; valid AP/tax/period | Existing Vendor Bill Posting path | Dr GINR/Purchase Clearing + recoverable tax as supplied / Cr AP and withholding roles |
| Simultaneous receipt and bill | Same governed control/receipt/bill occurrence | Receipt/method state and zero unmatched clearing | Exact line match, ownership, method, AP/tax readiness | One source-locked composite Posting call | Dr Inventory + tax / Cr AP and withholding; no transient GRNI/GINR |
| Receipt after bill/control | Bill match, control occurrence, physical warehouse receipt | Inventory receipt or in-transit-to-warehouse relocation; clears GINR if control now occurs | Match quantity/value, control time, transit state | Composite occurrence | Dr Inventory or Inventory in Transit / Cr GINR for matched amount; unbilled excess uses GRNI |
| Vendor Bill matched to prior receipt | Receipt event and provisional value, bill commercial/tax values, exact line match | GRNI clearing and source-linked cost-correction request for price delta | No duplicate/overmatch; FX and tax separated | Vendor Bill path plus approved Inventory correction output | Dr GRNI at provisional matched amount; Inventory/COGS destination delta as calculated; tax; Cr AP |
| Cash Purchase | Control/receipt/payment in one occurrence | Receipt/method state/stock and cash/AP-tax output | Ownership, source cost, cash, tax, method | Existing cash-purchase source lock | Dr Inventory + tax / Cr cash and withholding; no clearing if truly simultaneous |
| Price-only Vendor Credit | Linked acquisition/match and commercial/tax credit | Zero-quantity cost correction and on-hand/consumed allocation | Price reduction classification, source ancestry, no physical claim | Vendor Credit + correction plan | Dr AP / Cr tax as applicable and Inventory/COGS correction destinations |
| Billed Purchase Return | Eligible owned quantity/identity, original match, current method carrying cost, linked credit | Outbound event, method reduction, purchase-return variance | Availability, identity, method, credit/tax link | Purchase-return occurrence | Cr Inventory at carrying cost; Dr AP/tax reversal at commercial values; explicit variance line for difference |
| Unbilled Purchase Return | Eligible quantity and linked GRNI receipt amount | Outbound event and GRNI clear | Receipt link, outstanding GRNI, method cost | Purchase-return occurrence | Cr Inventory at carrying cost; Dr GRNI at linked provisional amount; explicit variance difference |
| Sales control transfer | Delivery acceptance, Sales revenue/AR or contract-asset/tax outputs, Inventory issue request | Issue allocation, stock/method reduction, COGS value | Same control date/period, availability/identity, tax and Sales readiness | One combined source-locked Posting call | Sales lines and Dr COGS / Cr Inventory in one ordered journal/occurrence; no period split |
| Later Sales Invoice | Prior recognition occurrence and billing/tax output | No new Inventory issue | Quantity/value not already billed; original recognition retained | Existing Sales Invoice path adapted at boundary | Reclass unbilled AR/contract asset to AR and tax as policy requires; no COGS/Inventory |
| Accepted Sales Return | Linked original issue allocation, accepted quantity/identity, latest corrected issue cost, Credit Memo output if simultaneous | Receipt event, restored method state, blocked/available status | Original issue and remaining return eligibility; inspection; period | Return occurrence | Dr Inventory / Cr COGS at corrected original issue cost; Credit Memo AR/revenue/tax lines distinct but linkable |
| Goods Issue | Approved source class and destination role, quantity/identity/method cost | Issue event, method/stock reduction | Destination permitted; WIP rejected until Production certified | Existing goods-issue source lock | Dr configured expense/project asset / Cr Inventory |
| Positive adjustment/count | Ownership evidence, approved measured cost per method | Receipt/adjustment event and method increase | WAC pool/provisional hierarchy; FIFO measured cost; Specific identity or quarantine | Existing adjustment/count shell | Dr Inventory / Cr adjustment/variance role |
| Negative adjustment/count | Eligible quantity/identity and method carrying value | Issue/adjustment event and method reduction | Availability, reason/approval | Existing adjustment/count shell | Dr adjustment/variance / Cr Inventory |
| Same-scope transfer | Source/destination physical state and carrying value | Paired dispatch/receipt/location events; method company value unchanged | Conservation, identity, transit status | Conditional | No journal unless configured GL account/dimension changes |
| Cross-scope same-entity transfer | Source method carrying value and target scope/method policy | Source removal, destination addition at exactly same value | Compatible policy; no profit; both legs linked | Conditional reclassification | Dr destination Inventory / Cr source Inventory only when control account/dimension requires |
| Inbound consignment receipt | Custody terms, physical quantity/identity | Custody event only | Explicit no-control evidence | None | No journal, AP, owned value, or COGS |
| Consignment ownership conversion | Contract cost/control event, custody identity/quantity | Owned acquisition then issue if simultaneously consumed | Terms, source cost, availability, AP/tax boundary | Composite if simultaneous | Acquisition Inventory/AP or GRNI, followed by issue destination in same occurrence when consumed |
| Opening conversion | Approved batch/line quantities, method state, gross value, allowance, full Trial Balance evidence | Opening events/method state/projections and batch control | One cut-off; exact method state; complete evidence; suspense clears | Governed opening source lock | Inventory and allowance roles against Opening Conversion Suspense; full batch clears suspense against evidenced non-inventory/equity balances |
| Landed cost/cost correction | Approved source amount, receipt ancestry, replay result, destination allocations | Zero-quantity correction event, new method-state versions, bridge | Attribution, allocation exactness, Period/IAS 8 classification | Correction occurrence | Dr/Cr Inventory for on-hand, COGS/expense/WIP or approved period destination for consumed, against source clearing/AP/variance as classified |
| NRV write-down | Approved assessment, gross cost, NRV, prior allowance | Zero-quantity allowance event | Item/group grain/evidence; lower-of-cost; open/adjusting period | NRV occurrence | Dr NRV loss / Cr inventory allowance |
| NRV reversal | Linked write-down and revised NRV | Capped allowance reversal | Cannot exceed related allowance or historical-cost ceiling | NRV occurrence | Dr allowance / Cr reversal of loss, capped |
| Write-off/disposal | Eligible quantity/identity, method carrying value, allowance share, reason | Issue/disposal event and closure | Approval, reason, identity, no hidden sale | Issue/disposal occurrence | Dr loss/expense, release allowance as applicable / Cr Inventory |
| Negative deficit settlement | Prior provisional deficit, qualifying receipt, actual method cost | Deficit settlement and exact provisional-to-actual delta | FIFO/WAC only; open period; close gate | Correction occurrence | Inventory/COGS or destination variance lines exactly as settlement plan determines |
| Reversal | Original event, allocations/method versions/journal, reversal date/reason | Exact opposite event and restored state | Lifecycle, period, no duplicate reversal | Existing Kernel reversal through governed Inventory source | Exact journal reversal plus any current-period correction plan required by frozen period policy |

## 6. Security and caller blueprint

- Public clients call only governed source-document commands and read-only reports.
- Inventory method calculators, projection writers, event committers, and Posting adapters
  are not directly executable by `anon`, `authenticated`, or general helpers.
- `fn_receive_inventory(jsonb)` must lose public/authenticated execution before its
  callers cut over. The four lower-level helper grants are already revoked and remain so.
- Every `SECURITY DEFINER` function must fix its search path, validate tenant/source
  ownership, and appear in the writer census.
- Direct DML remains denied for current and target derived tables.
- Migration/replay helpers can operate only through the same governed event services;
  no owner, maintenance, replica, or guard bypass is part of this blueprint.
- The journal Kernel guard remains enforced and unchanged.

## 7. Unsupported and deferred callers

Production/MRP, advanced WMS optimization, intercompany pricing/elimination/tax, and
uncertified foreign-currency source callers receive an explicit unsupported-capability
failure. No generic source type, default account, zero-cost receipt, or heuristic route
is permitted as a temporary substitute.
