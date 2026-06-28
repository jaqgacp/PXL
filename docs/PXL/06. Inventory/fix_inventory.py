import os
import glob
import re

root = r'C:\Users\Jeric Art Gumacal\Desktop\PXL - Lovable\06. Inventory'
files = glob.glob(os.path.join(root, '**', '*.md'), recursive=True)

arch_note = "\n\n**Critical UX/GL Rule:** The system MUST auto-fetch the Item's default Revenue, Expense, COGS, and Inventory GL accounts in the background to auto-generate the Journal Entry. Encoders MUST NEVER manually select a GL account for standard items.\n"

for file in files:
    with open(file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    # 1. Master Data (Items)
    if '01. Items.md' in file:
        # UI table replacement
        content = content.replace('| Base UOM | Base Unit of Measure (e.g., PCS, BOX). | Yes | Dropdown |', '| Default UOM | Base Unit of Measure. | Yes | Dropdown linked to UOM |')
        content = content.replace('| Sales VAT Code | VAT treatment (Vatable, Zero-Rated, Exempt). | Yes | Dropdown |', '| Default Tax Code | VAT treatment. | Yes | Dropdown linked to Tax Codes |')
        content = content.replace('| Purchase VAT Code | VAT treatment on purchases. | Yes | Dropdown |\n', '')
        content = content.replace('| Income Account | GL account for revenue posting. | Yes | Dropdown (Chart of Accounts) |', '| Revenue Account | GL account for revenue posting. | Yes | Dropdown linked to Chart of Accounts |\n| Expense Account | GL account for expenses. | Yes | Dropdown linked to Chart of Accounts |')
        content = content.replace('| Expense/COGS Account| GL account for Cost of Goods Sold. | Yes | Dropdown (Chart of Accounts) |', '| COGS Account | GL account for Cost of Goods Sold. | Yes | Dropdown linked to Chart of Accounts |')
        content = content.replace('| Inventory Account | GL account for Asset value. | Conditional | Dropdown (Chart of Accounts) |', '| Inventory Account | GL account for Asset value. | Conditional | Dropdown linked to Chart of Accounts |')
        
        # Additional UI fields (Default Cost, Default Price)
        content = content.replace('| Default Warehouse | The standard receiving/shipping location. | Optional | Dropdown (Links to Warehouses) |', '| Default Warehouse | The standard receiving/shipping location. | Optional | Dropdown (Links to Warehouses) |\n| Default Cost | Standard purchase cost. | Optional | Numeric |\n| Default Price | Standard selling price. | Optional | Numeric |')
        
        # DB table replacement
        content = content.replace('| `base_uom` | Text | Required | e.g., \'PCS\', \'KGS\'. |', '| `default_uom_id` | UUID | Required, Foreign Key | Links to `uom.id`. |')
        content = content.replace('| `sales_vat_code` | Text | Required | `vatable`, `zero_rated`, `exempt`. |', '| `default_tax_code_id` | UUID | Required, Foreign Key | Links to `tax_codes.id`. |')
        content = content.replace('| `purchase_vat_code` | Text | Required | `vatable`, `zero_rated`, `exempt`, `capital_goods`. |\n', '')
        content = content.replace('| `income_account_id` | UUID | Nullable, Foreign Key | Links to `accounts.id`. |', '| `revenue_account_id` | UUID | Nullable, Foreign Key | Links to `accounts.id`. |\n| `expense_account_id` | UUID | Nullable, Foreign Key | Links to `accounts.id`. |')
        content = content.replace('| `cogs_account_id` | UUID | Nullable, Foreign Key | Links to `accounts.id`. |', '| `cogs_account_id` | UUID | Nullable, Foreign Key | Links to `accounts.id`. |')
        
        # Add default_cost, default_price to DB table
        content = content.replace('| `costing_method` | Text | Nullable | `fifo`, `moving_average`, `standard`. |', '| `costing_method` | Text | Nullable | `fifo`, `moving_average`, `standard`. |\n| `default_cost` | Numeric(15,4) | Nullable | Standard cost. |\n| `default_price` | Numeric(15,4) | Nullable | Standard price. |')
    
    # 2. Cascading Lookups
    # Customer/Vendor
    content = re.sub(r'\|\s*(Customer|Vendor)\s*\|.*?\|.*?\|\s*(Dropdown.*?\||Text.*?\|)', 
                     r'| \1 | Select \1. | Yes | Dropdown linked to Master Data. UPON SELECTION, system MUST instantly auto-fill: Address, TIN, Credit Terms, and Tax Type. |', content, flags=re.IGNORECASE)

    # Item
    content = re.sub(r'\|\s*Item Code\s*\|.*?\|.*?\|\s*(Dropdown.*?\||Text.*?\|)',
                     r'| Item Code | Select item. | Yes | Dropdown linked to Items. UPON SELECTION, instantly auto-fills Description, UOM, Unit Price/Cost, and Tax Code. |', content, flags=re.IGNORECASE)

    # 3. Automated Account Determination
    # Explicitly remove manual GL Account from line items
    # Also remove `Expense Account`, `Income Account`
    if 'Line Items' in content:
        parts = content.split('Line Items')
        line_items_section = parts[1]
        
        line_items_section = re.sub(r'\|\s*(Expense Account|GL Account|Income Account)\s*\|.*?\|.*?\|.*?\|\n', '', line_items_section, flags=re.IGNORECASE)
        line_items_section = re.sub(r'\|\s*(expense_account_id|gl_account_id|income_account_id)\s*\|.*?\|.*?\|.*?\|\n', '', line_items_section, flags=re.IGNORECASE)
        
        content = parts[0] + 'Line Items' + line_items_section

    # Architectural Note
    if '**Critical UX/GL Rule:**' not in content:
        content += arch_note

    # 4. Dropdown Normalization
    content = re.sub(r'\|\s*UOM\s*\|(.*)\|.*\|.*\|', r'| UOM |\1| System | Dropdown linked to UOM |', content, flags=re.IGNORECASE)
    content = re.sub(r'\|\s*Payment Terms\s*\|(.*)\|.*\|.*\|', r'| Payment Terms |\1| Yes | Dropdown linked to Payment Terms |', content, flags=re.IGNORECASE)
    content = re.sub(r'\|\s*EWT\s*\|(.*)\|.*\|.*\|', r'| EWT |\1| Yes | Dropdown linked to EWT Codes |', content, flags=re.IGNORECASE)
    content = re.sub(r'\|\s*Tax Type\s*\|(.*)\|.*\|.*\|', r'| Tax Type |\1| Yes | Dropdown linked to Tax Types |', content, flags=re.IGNORECASE)
    content = re.sub(r'\|\s*Reason Code\s*\|(.*)\|.*\|.*Dropdown.*\|', r'| Reason Code |\1| Yes | Dropdown linked to Reason Codes |', content, flags=re.IGNORECASE)
    content = re.sub(r'\|\s*Issue Type\s*\|(.*)\|.*\|.*Dropdown.*\|', r'| Issue Type |\1| Yes | Dropdown linked to Issue Types |', content, flags=re.IGNORECASE)
    
    if content != original_content:
        with open(file, 'w', encoding='utf-8') as f:
            f.write(content)
        print("Updated:", file)