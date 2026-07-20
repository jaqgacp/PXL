# PXL Philippine TIN Standard

Status: SYSTEM-WIDE STANDARD. This is the source of truth for Philippine TIN handling across PXL ERP.

## 1. Canonical Format

All Philippine TIN values must display as:

`XXX-XXX-XXX-XXXXX`

This represents:

- First 9 digits: taxpayer identification number.
- Last 5 digits: BIR branch identification code.

Examples:

- `123-456-789-00000`
- `123-456-789-00001`
- `123-456-789-00015`
- `123-456-789-00120`

Never persist or display 3-digit or 4-digit branch codes.

## 2. Storage And Validation

PXL may store either:

- One normalized full TIN value formatted as `XXX-XXX-XXX-XXXXX`, or
- A 9-digit taxpayer number plus a separate 5-digit branch code.

Validation rules:

- Taxpayer number: exactly 9 digits.
- Branch code: exactly 5 digits.
- Default branch: `00000`.
- Formatted display: always `XXX-XXX-XXX-XXXXX`.

## 3. UI Behavior

Every TIN input must:

- Format while typing.
- Preserve formatting when editing.
- Accept search using raw digits, for example `12345678900000`.
- Accept search using formatted values, for example `123-456-789-00000`.
- Display the canonical formatted value everywhere.

If a separate branch field is shown, label it `TIN Branch` and store/display exactly 5 digits.

## 4. Master Data Scope

This standard applies to:

- Company
- Company Branches
- Customers
- Suppliers
- Employees
- Government Agencies
- Tax Profiles
- Registration Profiles
- Business Partners
- Any future module that stores Philippine TIN values

## 5. Transaction Scope

Transaction snapshots, printed documents, PDFs, reports, exports, and API responses must use the same canonical format.

This includes sales, purchasing, banking, payments, journal, inventory, and future document workspaces.

## 6. Import, Export, API, And Reports

CSV import, Excel import, API payloads, report tables, PDF output, printed documents, and BIR working papers must normalize and display TIN values as `XXX-XXX-XXX-XXXXX`.

Imports may accept raw digits or formatted values, but stored/displayed values must use the canonical format.

## 7. BIR Readiness

Future BIR modules must inherit this standard without additional refactoring, including:

- 2307
- 2306
- 2550Q
- 2551Q
- 1701
- 1702
- 1601EQ
- 1601FQ
- 1604E
- SLSP
- SAWT
- RELIEF
- QAP
- CAS Export
