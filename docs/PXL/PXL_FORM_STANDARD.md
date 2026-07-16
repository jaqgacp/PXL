# PXL Form Standard

Status: OFFICIAL FORM FIELD STANDARD

Forms must feel like ERP data-entry surfaces, not generic web forms.

## Fields

- Editable fields use `pxl-input`.
- Readonly business facts use `pxl-readonly-field`.
- Field labels use 12px medium text.
- Body values use 13px regular text.
- Readonly fields must not look disabled.
- Required fields must be clear without relying on color alone.

## Lookups

Customer, Supplier, Item, Employee, Project, Cost Center, Location, and GL Account lookups must share:

- Search
- Keyboard navigation
- Dropdown behavior
- Clear button where applicable
- Consistent styling
- Future recent selections

## States

Every field component must define hover, focus, disabled, readonly, invalid, and loading states.
