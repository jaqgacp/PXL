# The Master Pharmacy — End-to-End Findings

## Accountant’s scope

I approached this as the accountant for a VAT-registered retail pharmacy with a high-volume month and two operating branches. The intended period is **1–31 July 2026**, with PHP as the functional currency and 12% VAT on regular taxable goods.

This is an honest working paper. I separated what I could verify in the repository/local database from what I could not execute because the product has no Master Pharmacy tenant, pharmacy master data, or authenticated pharmacy user.

## Proposed company setup

| Area | Master Pharmacy setup to create |
|---|---|
| Company | The Master Pharmacy; VAT registered; retail pharmacy line of business; July 2026 open fiscal period |
| Branch 1 | MPH-MAIN — Main Branch |
| Branch 2 | MPH-EAST — East Branch |
| Warehouses | MPH-MAIN-WH and MPH-EAST-WH, one active warehouse per branch |
| Departments | Pharmacy Retail, Front Store, Administration |
| Cost centers | CC-MAIN-PHARMACY, CC-EAST-PHARMACY, CC-ADMIN |
| VAT | Output VAT 12%; Input VAT 12%; zero-rated/exempt codes retained for exceptional items |
| Core GL | Inventory, COGS, Sales, Input VAT, Output VAT, Accounts Payable, Accounts Receivable, Cash, Bank, Inventory Shrinkage |
| Controls | Open fiscal period, number series for PO/RR/VB/CP/SI/OR/PV, GL posting configuration, active void reasons, authenticated company membership, approval roles |

## Pharmacy master data required

The following representative items would be loaded as `inventory_item` records with standard cost, UOM, VAT code, inventory account, COGS account, sales account, and costing method:

| SKU | Description | Opening qty | Cost | Selling price |
|---|---|---:|---:|---:|
| AMOX-500 | Amoxicillin 500mg, box of 20 | 240 | 85.00 | 125.00 |
| PARA-500 | Paracetamol 500mg, box of 100 | 360 | 42.00 | 65.00 |
| VITC-100 | Vitamin C 500mg, bottle of 100 | 180 | 110.00 | 165.00 |
| BP-STD | Digital blood-pressure monitor | 30 | 950.00 | 1,350.00 |
| MASK-50 | Surgical masks, box of 50 | 300 | 75.00 | 120.00 |
| SYR-5ML | Disposable syringes, box of 100 | 120 | 140.00 | 220.00 |

Suppliers should include a wholesaler for medicines, a medical-device distributor, and a consumables supplier. Customers should include walk-in retail, a company account, and a clinic account. Payment terms should include cash, NET15, and NET30.

## Intended July transaction run

1. Create the company, two branches, warehouses, departments, cost centers, VAT codes, chart of accounts, fiscal period, number series, posting configuration, users, roles, suppliers, customers, UOMs, categories, and pharmacy items.
2. Enter opening stock into each warehouse using approved opening inventory evidence.
3. Create and approve a Main Branch PO for 500 AMOX-500, 600 PARA-500, and 200 MASK-50.
4. Create and confirm a Main Branch receiving report for the delivered quantities. Inventory receipt should increase warehouse stock and create immutable inventory transactions.
5. Create and post the vendor bill from that receipt. Expected accounting is Inventory/Input VAT debit and Accounts Payable credit.
6. Record a NET30 payment voucher against the approved bill. Expected accounting is Accounts Payable debit and Bank/Cash credit.
7. Repeat a smaller East Branch purchase and receipt for VITC-100, BP-STD, and SYR-5ML.
8. Record a cash purchase of inventory at the East Branch, with a warehouse selected. Expected posting is inventory or expense debit, Input VAT debit, and Cash credit.
9. Post representative sales invoices/cash sales in both branches. Expected posting is Sales and Output VAT, plus inventory issue and COGS at the item’s standard/WAC cost.
10. Process one customer receipt, one supplier payment, one stock adjustment for expiry/shrinkage, and one inter-branch transfer.
11. Reconcile the month: Trial Balance, Inventory Valuation, Inventory Movements, Sales Register, Purchase Register, Input VAT, Output VAT, VAT return totals, AP aging, AR aging, and branch/cost-center profitability.

## What I actually verified

- The local Supabase database was running with five existing demo companies and 91 existing items. There was no Master Pharmacy company or pharmacy-specific fixture.
- Migration `20260718000001_purchase_dimensions_inventory_receiving.sql` applied successfully to the local database.
- The recent item-picker corrections and purchase dimension UI compile successfully.
- `npm run test:sales-invoice-draft-state` passed 4/4.
- `npm run test:transaction-workspace` passed 11/11.
- Existing seeds target PXL Demo Trading Corporation and ABC Trading Corporation; they do not establish The Master Pharmacy workflow.

## Execution result

I could not honestly mark the July transaction chain as posted. The blocking condition is setup data and authorization, not an accounting calculation: there is no Master Pharmacy tenant, no pharmacy master records, and no authenticated Master Pharmacy user/membership against which to run the RPC workflow. Creating transactions under an existing demo company would produce evidence for the wrong legal entity and would be misleading.

Therefore the following remain **not executed for Master Pharmacy**: PO approval, RR confirmation, vendor-bill posting, payment voucher, cash purchase posting, sales posting, inventory issue, inter-branch transfer, VAT reconciliation, and month-end close.

## Defects and risks found

### Blocking or high-risk

- A pharmacy-specific end-to-end setup/transaction fixture is missing.
- The hosted database may not yet have migration `20260718000001`; until it is applied, the new warehouse/department/cost-center fields and guarded inventory receipt behavior are unavailable.
- Inventory sales/posting require active warehouse stock, standard cost, inventory/COGS accounts, open fiscal periods, and complete GL posting configuration. Missing any one produces a posting blocker.
- RLS and membership checks require an authenticated user belonging to the company. A database/service-role check is not equivalent to an accountant’s user workflow.
- Segregation-of-duties approval rules may prevent one user from creating, approving, and posting the same document.
- Payment vouchers require an approved bill and a configured bank/cash account.

### Material usability defects to resolve before live pharmacy testing

- Editing an item currently risks clearing its sales, COGS, inventory, and purchase-expense account mappings because the edit form does not reliably reload those links.
- Editing an item category has the same risk for default GL mappings.
- Item UOM selection is limited to base units even though UOM conversions exist; pharmacy purchasing/selling pack sizes should be tested explicitly.
- A new Receiving Report initially defaults dimensions from the first globally loaded warehouse/department/cost center. Selecting a PO corrects this, but a manually started document can begin with a wrong-branch dimension.
- Required setup fields have limited client-side validation; failures surface as generic database errors instead of clear accounting/setup guidance.

## Accountant’s acceptance criteria

I would not sign off the Master Pharmacy month until:

1. The company and both branches are created under the correct legal entity and VAT registration.
2. Every inventory SKU has UOM, VAT, standard cost, inventory, COGS, and sales mappings.
3. Both warehouses have opening stock and the stock ledger agrees to the physical count.
4. PO → RR → VB → PV works for both branches with source-document traceability.
5. Sales reduce the correct warehouse and recognize COGS and Output VAT.
6. VAT reports reconcile to posted purchase and sales tax-detail entries.
7. Branch, department, cost-center, AP, AR, inventory, and GL balances reconcile for the month.
8. The item-edit/account-mapping and wrong-branch Receiving Report defects are fixed or explicitly controlled.

**Conclusion:** the application has the structural workflow for this pharmacy scenario, and the focused UI/build tests are green, but I cannot claim an end-to-end Master Pharmacy transaction month was completed. The missing legal-entity fixture, authenticated tenant setup, and the defects above must be addressed before that conclusion is supportable.
