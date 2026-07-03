# PXL Schema Summary

GENERATED FILE — do not hand-edit. Regenerate with `scripts/gen_schema_summary.sh` after adding migrations (CI does not enforce freshness; regenerate in any session that adds a migration).

Maps every database object to the migration holding its CURRENT definition, so agents do not grep the full chain. Column "Defs" counts how many migrations (re)define the object — a high count means the object has history worth checking before editing.

Generated: 2026-07-03. Migrations scanned: 72. Tests present: 18.

## Functions (144)

| Function | Latest definition | Defs |
| -------- | ----------------- | ---- |
| `can_admin_company` | `20260701000006_permissions_hardening.sql` | 3 |
| `fn_acknowledge_supplier_debit_memo` | `20260630000021_gap_fill.sql` | 2 |
| `fn_add_cost_layer` | `20260630000028_inventory.sql` | 1 |
| `fn_ap_aging_asof` | `20260702000003_ar_ap_aging_asof_rpcs.sql` | 1 |
| `fn_apply_vendor_credit` | `20260701000011_vendor_credit_application_reversal.sql` | 4 |
| `fn_approve_petty_cash_voucher` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_approve_purchase_order` | `20260630000021_gap_fill.sql` | 2 |
| `fn_approve_sales_invoice` | `20260701000008_accounting_readiness_approval.sql` | 3 |
| `fn_approve_vendor_bill` | `20260701000008_accounting_readiness_approval.sql` | 3 |
| `fn_ar_aging_asof` | `20260702000003_ar_ap_aging_asof_rpcs.sql` | 1 |
| `fn_atc_code_is_current` | `20260701000018_atc_effective_date_governance.sql` | 1 |
| `fn_atc_code_used` | `20260701000018_atc_effective_date_governance.sql` | 1 |
| `fn_audit_trigger` | `20260630000021_gap_fill.sql` | 2 |
| `fn_block_pv_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_block_receipt_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_block_si_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_block_vb_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_bounce_receipt` | `20260702000009_tax_ledger_void_reversal.sql` | 4 |
| `fn_bt_reverse_je` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_can_perform` | `20260702000010_can_perform_role_actions.sql` | 1 |
| `fn_cancel_amortization_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_cancel_bank_adjustment` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_check_voucher` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_fund_transfer` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_inter_branch_transfer` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_payment_voucher` | `20260702000009_tax_ledger_void_reversal.sql` | 3 |
| `fn_cancel_petty_cash_voucher` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_purchase_order` | `20260630000021_gap_fill.sql` | 2 |
| `fn_cancel_revenue_recognition_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_complete_purchase_return` | `20260630000021_gap_fill.sql` | 3 |
| `fn_compute_depr_schedule` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_confirm_receiving_report` | `20260630000021_gap_fill.sql` | 2 |
| `fn_consume_cost_layers` | `20260630000028_inventory.sql` | 1 |
| `fn_create_amortization_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_create_revenue_recognition_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_dispose_fixed_asset` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_enforce_approval_sod` | `20260703000001_approval_sod_enforcement.sql` | 1 |
| `fn_ensure_stock_balance` | `20260630000028_inventory.sql` | 1 |
| `fn_execute_recurring_template` | `20260630000025_accounting_module.sql` | 1 |
| `fn_form2307_period_bounds` | `20260703000005_report_snapshots_form2307.sql` | 1 |
| `fn_form2307_report_payload` | `20260703000005_report_snapshots_form2307.sql` | 1 |
| `fn_generate_form_2307_issued` | `20260702000007_form2307_version_supersede.sql` | 2 |
| `fn_generate_tax_calendar` | `20260628000005_sprint2_tax.sql` | 1 |
| `fn_generate_tax_calendar_trigger` | `20260628000005_sprint2_tax.sql` | 1 |
| `fn_grant_all_users_on_new_company` | `20260630000021_gap_fill.sql` | 2 |
| `fn_grant_creator_company_ownership` | `20260630000021_gap_fill.sql` | 2 |
| `fn_grant_new_user_all_companies` | `20260630000021_gap_fill.sql` | 2 |
| `fn_guard_atc_code_history` | `20260701000018_atc_effective_date_governance.sql` | 1 |
| `fn_guard_form2307_snapshot_immutable` | `20260703000005_report_snapshots_form2307.sql` | 1 |
| `fn_guard_vat_return_snapshot_immutable` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_mark_tax_event_filed` | `20260630000021_gap_fill.sql` | 2 |
| `fn_next_document_number` | `20260630000021_gap_fill.sql` | 3 |
| `fn_post_amortization_entry` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_post_bank_adjustment` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_post_cash_purchase` | `20260703000002_vat_ledger_completeness.sql` | 4 |
| `fn_post_check_voucher` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_post_credit_memo` | `20260630000022_tax_ledger_completeness.sql` | 3 |
| `fn_post_debit_memo` | `20260630000022_tax_ledger_completeness.sql` | 3 |
| `fn_post_depreciation_entry` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_post_fund_transfer` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_post_goods_issue` | `20260630000028_inventory.sql` | 1 |
| `fn_post_inter_branch_transfer` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_post_manual_je` | `20260630000025_accounting_module.sql` | 1 |
| `fn_post_payment_voucher` | `20260701000016_pv_ewt_explicit_basis.sql` | 6 |
| `fn_post_petty_cash_replenishment` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_post_physical_count` | `20260630000028_inventory.sql` | 1 |
| `fn_post_receipt` | `20260701000017_customer_cwt_defaults.sql` | 5 |
| `fn_post_revenue_recognition_entry` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_post_sales_invoice` | `20260703000002_vat_ledger_completeness.sql` | 6 |
| `fn_post_stock_adjustment` | `20260630000028_inventory.sql` | 1 |
| `fn_post_stock_transfer` | `20260630000028_inventory.sql` | 1 |
| `fn_post_vendor_bill` | `20260703000002_vat_ledger_completeness.sql` | 4 |
| `fn_post_vendor_credit` | `20260630000022_tax_ledger_completeness.sql` | 4 |
| `fn_receive_inventory` | `20260630000028_inventory.sql` | 1 |
| `fn_record_impairment` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_register_fixed_asset` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_report_snapshot_key_uuid` | `20260703000006_report_snapshots_vat_exports.sql` | 1 |
| `fn_require_admin_for_accounting_lifecycle` | `20260702000010_can_perform_role_actions.sql` | 3 |
| `fn_require_customer_cwt_default` | `20260701000018_atc_effective_date_governance.sql` | 2 |
| `fn_require_pv_ewt_ready_status` | `20260701000013_pv_ewt_atc_validation.sql` | 1 |
| `fn_require_pvl_ewt_validation` | `20260701000016_pv_ewt_explicit_basis.sql` | 2 |
| `fn_require_receipt_line_cwt_validation` | `20260701000017_customer_cwt_defaults.sql` | 1 |
| `fn_require_si_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` | 1 |
| `fn_require_si_line_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_si_vat_registration_status` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vat_registered_company` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vat_return_reconciled` | `20260702000004_vat_ledger_gl_reconciliation.sql` | 1 |
| `fn_require_vat_return_registered_company` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vb_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` | 1 |
| `fn_require_vb_line_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vb_vat_registration_status` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_required_approval_workflow` | `20260703000001_approval_sod_enforcement.sql` | 1 |
| `fn_reverse_je` | `20260630000025_accounting_module.sql` | 1 |
| `fn_reverse_tax_detail_entries` | `20260702000009_tax_ledger_void_reversal.sql` | 1 |
| `fn_reverse_vendor_credit_application` | `20260701000011_vendor_credit_application_reversal.sql` | 1 |
| `fn_revert_si_to_draft` | `20260630000021_gap_fill.sql` | 2 |
| `fn_revert_vendor_bill_to_draft` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_cash_purchase` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_cash_sale` | `20260703000002_vat_ledger_completeness.sql` | 4 |
| `fn_save_credit_memo` | `20260630000022_tax_ledger_completeness.sql` | 4 |
| `fn_save_debit_memo` | `20260630000022_tax_ledger_completeness.sql` | 4 |
| `fn_save_payment_voucher` | `20260701000016_pv_ewt_explicit_basis.sql` | 3 |
| `fn_save_purchase_order` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_purchase_return` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_receipt` | `20260701000017_customer_cwt_defaults.sql` | 4 |
| `fn_save_receiving_report` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_sales_invoice` | `20260630000021_gap_fill.sql` | 3 |
| `fn_save_supplier_debit_memo` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_vendor_bill` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_vendor_credit` | `20260630000021_gap_fill.sql` | 2 |
| `fn_send_supplier_debit_memo` | `20260630000021_gap_fill.sql` | 2 |
| `fn_set_updated_at` | `20260629000001_dashboard.sql` | 1 |
| `fn_ship_purchase_return` | `20260630000021_gap_fill.sql` | 2 |
| `fn_snapshot_books_export` | `20260703000009_report_snapshots_books_exports.sql` | 1 |
| `fn_snapshot_cas_export` | `20260703000008_report_snapshots_cas_exports.sql` | 1 |
| `fn_snapshot_form2307_issued` | `20260703000005_report_snapshots_form2307.sql` | 1 |
| `fn_snapshot_vat_export` | `20260703000006_report_snapshots_vat_exports.sql` | 1 |
| `fn_snapshot_vat_return` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_snapshot_wht_export` | `20260703000007_report_snapshots_wht_exports.sql` | 1 |
| `fn_supersede_form_2307_issued` | `20260702000007_form2307_version_supersede.sql` | 1 |
| `fn_sync_number_series_shape` | `20260702000001_number_series_document_code_alignment.sql` | 1 |
| `fn_transfer_fixed_asset` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_update_form_2307_issued_status` | `20260701000015_form2307_issued_generation_rpc.sql` | 1 |
| `fn_update_payment_tracking` | `20260630000021_gap_fill.sql` | 2 |
| `fn_update_wac` | `20260630000028_inventory.sql` | 1 |
| `fn_validate_company_vat_code` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_validate_payment_voucher_ewt_ready` | `20260701000016_pv_ewt_explicit_basis.sql` | 2 |
| `fn_validate_payment_voucher_line_ewt` | `20260701000018_atc_effective_date_governance.sql` | 3 |
| `fn_validate_receipt_cwt_ready` | `20260701000017_customer_cwt_defaults.sql` | 1 |
| `fn_validate_receipt_line_cwt` | `20260701000018_atc_effective_date_governance.sql` | 2 |
| `fn_validate_sales_invoice_accounting_ready` | `20260701000008_accounting_readiness_approval.sql` | 1 |
| `fn_validate_sales_invoice_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_validate_supplier_atc_default` | `20260701000018_atc_effective_date_governance.sql` | 2 |
| `fn_validate_vendor_bill_accounting_ready` | `20260701000008_accounting_readiness_approval.sql` | 1 |
| `fn_validate_vendor_bill_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_vat_gl_reconciliation` | `20260702000005_gl_reversal_visibility.sql` | 2 |
| `fn_vat_return_period_bounds` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_vat_return_report_payload` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_void_sales_invoice` | `20260702000009_tax_ledger_void_reversal.sql` | 4 |
| `fn_void_vendor_bill` | `20260702000009_tax_ledger_void_reversal.sql` | 4 |
| `fn_wht_gl_reconciliation` | `20260703000007_report_snapshots_wht_exports.sql` | 1 |
| `is_any_company_admin` | `20260630000021_gap_fill.sql` | 2 |
| `is_company_member` | `20260630000021_gap_fill.sql` | 2 |
| `update_updated_at` | `20260628000001_companies.sql` | 1 |

## Views (19)

| View | Latest definition | Defs |
| ---- | ----------------- | ---- |
| `vw_ap_aging` | `20260630000021_gap_fill.sql` | 2 |
| `vw_credit_memo_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_customer_ledger` | `20260630000021_gap_fill.sql` | 3 |
| `vw_cwt_summary_ar` | `20260703000007_report_snapshots_wht_exports.sql` | 1 |
| `vw_debit_memo_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_deposits_in_transit` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `vw_ewt_summary_ap` | `20260702000009_tax_ledger_void_reversal.sql` | 5 |
| `vw_general_ledger` | `20260702000005_gl_reversal_visibility.sql` | 2 |
| `vw_input_vat_review` | `20260703000003_vat_review_views_ledger_backed.sql` | 4 |
| `vw_output_vat_review` | `20260703000003_vat_review_views_ledger_backed.sql` | 2 |
| `vw_outstanding_checks` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `vw_payment_register` | `20260630000021_gap_fill.sql` | 2 |
| `vw_receipt_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_sales_invoice_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_sdm_register` | `20260630000021_gap_fill.sql` | 2 |
| `vw_slp_export` | `20260630000021_gap_fill.sql` | 2 |
| `vw_supplier_ledger` | `20260630000021_gap_fill.sql` | 2 |
| `vw_trial_balance` | `20260702000005_gl_reversal_visibility.sql` | 2 |
| `vw_vendor_bill_register` | `20260630000021_gap_fill.sql` | 2 |

## Tables (146)

| Table | Created in | Alters | Last altered in |
| ----- | ---------- | ------ | --------------- |
| `amortization_entries` | `20260630000026_amortization_revenuerecon.sql` | 1 | `20260630000026_amortization_revenuerecon.sql` |
| `amortization_schedules` | `20260630000026_amortization_revenuerecon.sql` | 1 | `20260630000026_amortization_revenuerecon.sql` |
| `approval_instances` | `20260628000002_sprint1.sql` | 2 | `20260703000001_approval_sod_enforcement.sql` |
| `approval_workflow_steps` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `approval_workflows` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `asset_depreciation_entries` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `asset_disposals` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `asset_impairments` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `asset_transfers` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `atc_codes` | `20260628000003_sprint2.sql` | 5 | `20260701000018_atc_effective_date_governance.sql` |
| `bank_accounts` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bank_adjustments` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bank_recon_items` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bank_reconciliations` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bir_form_mappings` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `bir_forms` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `book_tax_reconciliation` | `20260701000004_income_tax.sql` | 0 | `—` |
| `branches` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `cas_attachment_register` | `20260701000005_audit_cas.sql` | 1 | `20260701000005_audit_cas.sql` |
| `cas_export_log` | `20260701000005_audit_cas.sql` | 2 | `20260703000008_report_snapshots_cas_exports.sql` |
| `cash_count_sheets` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `cash_purchase_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `cash_purchases` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `chart_of_accounts` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `check_voucher_lines` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `check_vouchers` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `companies` | `20260628000001_companies.sql` | 1 | `20260628000001_companies.sql` |
| `company_accounting_config` | `20260629000013_gl_core.sql` | 3 | `20260630000021_gap_fill.sql` |
| `compliance_1601eq_working_papers_headers` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `compliance_1601eq_working_papers_lines` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `compliance_1601fq_working_papers_headers` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `compliance_1601fq_working_papers_lines` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `compliance_ewt_working_papers_headers` | `20260629000006_ewt_working_papers.sql` | 1 | `20260629000006_ewt_working_papers.sql` |
| `compliance_ewt_working_papers_lines` | `20260629000006_ewt_working_papers.sql` | 1 | `20260629000006_ewt_working_papers.sql` |
| `compliance_fwt_working_papers_headers` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `compliance_fwt_working_papers_lines` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `compliance_profiles` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `compliance_pt_working_papers_headers` | `20260701000001_percentage_tax.sql` | 1 | `20260701000001_percentage_tax.sql` |
| `compliance_pt_working_papers_lines` | `20260701000001_percentage_tax.sql` | 1 | `20260701000001_percentage_tax.sql` |
| `compliance_vat_working_papers_headers` | `20260701000002_vat.sql` | 1 | `20260701000002_vat.sql` |
| `compliance_vat_working_papers_lines` | `20260701000002_vat.sql` | 1 | `20260701000002_vat.sql` |
| `cost_centers` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `credit_memo_lines` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `credit_memos` | `20260629000003_sprint5_ar.sql` | 4 | `20260630000022_tax_ledger_completeness.sql` |
| `currencies` | `20260628000002_sprint1.sql` | 2 | `20260628000004_fixes.sql` |
| `customers` | `20260628000003_sprint2.sql` | 3 | `20260701000017_customer_cwt_defaults.sql` |
| `dashboard_layouts` | `20260629000001_dashboard.sql` | 1 | `20260629000001_dashboard.sql` |
| `dashboard_widgets` | `20260629000001_dashboard.sql` | 1 | `20260629000001_dashboard.sql` |
| `debit_memo_lines` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `debit_memos` | `20260629000003_sprint5_ar.sql` | 4 | `20260630000022_tax_ledger_completeness.sql` |
| `delivery_receipt_lines` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `delivery_receipts` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `departments` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `employees` | `20260630000029_master_data_completion.sql` | 1 | `20260630000029_master_data_completion.sql` |
| `ewt_codes` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `ewt_returns` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `exchange_rates` | `20260628000002_sprint1.sql` | 2 | `20260628000004_fixes.sql` |
| `fiscal_periods` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `fiscal_years` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `fixed_asset_categories` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `fixed_assets` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `form_2306_issuances` | `20260701000003_withholding_tax.sql` | 1 | `20260701000003_withholding_tax.sql` |
| `form_2307_issuance_lines` | `20260630000022_tax_ledger_completeness.sql` | 1 | `20260630000022_tax_ledger_completeness.sql` |
| `form_2307_issuances` | `20260629000018_purchasing_full.sql` | 3 | `20260702000007_form2307_version_supersede.sql` |
| `form_2307_tracking` | `20260629000007_cwt_2307.sql` | 3 | `20260630000021_gap_fill.sql` |
| `fund_transfers` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `fwt_codes` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `fwt_returns` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `goods_issue_lines` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `goods_issues` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `income_tax_computations` | `20260701000004_income_tax.sql` | 0 | `—` |
| `inter_branch_transfers` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `inventory_cost_layers` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `inventory_transactions` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `item_categories` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `items` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `itr_filings` | `20260701000004_income_tax.sql` | 0 | `—` |
| `journal_entries` | `20260629000013_gl_core.sql` | 5 | `20260630000025_accounting_module.sql` |
| `journal_entry_lines` | `20260629000013_gl_core.sql` | 2 | `20260630000021_gap_fill.sql` |
| `mcit_computations` | `20260701000004_income_tax.sql` | 0 | `—` |
| `nolco_schedule` | `20260701000004_income_tax.sql` | 0 | `—` |
| `number_series` | `20260628000002_sprint1.sql` | 2 | `20260702000001_number_series_document_code_alignment.sql` |
| `payment_terms` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `payment_voucher_lines` | `20260629000017_purchasing.sql` | 3 | `20260701000016_pv_ewt_explicit_basis.sql` |
| `payment_vouchers` | `20260629000017_purchasing.sql` | 4 | `20260630000021_gap_fill.sql` |
| `percentage_tax_codes` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `petty_cash_funds` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `petty_cash_replenishments` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `petty_cash_vouchers` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `physical_count_sheet_lines` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `physical_count_sheets` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `pt_returns` | `20260701000001_percentage_tax.sql` | 1 | `20260701000001_percentage_tax.sql` |
| `purchase_order_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `purchase_orders` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `purchase_return_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `purchase_returns` | `20260629000018_purchasing_full.sql` | 3 | `20260630000021_gap_fill.sql` |
| `receipt_lines` | `20260629000003_sprint5_ar.sql` | 4 | `20260630000021_gap_fill.sql` |
| `receipts` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `receiving_report_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `receiving_reports` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `recurring_journal_template_lines` | `20260630000025_accounting_module.sql` | 1 | `20260630000025_accounting_module.sql` |
| `recurring_journal_templates` | `20260630000025_accounting_module.sql` | 1 | `20260630000025_accounting_module.sql` |
| `ref_atc_codes` | `20260629000007_cwt_2307.sql` | 1 | `20260629000007_cwt_2307.sql` |
| `ref_compliance_forms` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `ref_document_types` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `ref_feature_definitions` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `ref_payment_modes` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `ref_rdo_codes` | `20260628000001_companies.sql` | 1 | `20260628000001_companies.sql` |
| `ref_reason_codes` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `report_snapshots` | `20260703000004_report_snapshots_vat_returns.sql` | 2 | `20260703000005_report_snapshots_form2307.sql` |
| `revenue_recognition_entries` | `20260630000026_amortization_revenuerecon.sql` | 1 | `20260630000026_amortization_revenuerecon.sql` |
| `revenue_recognition_schedules` | `20260630000026_amortization_revenuerecon.sql` | 1 | `20260630000026_amortization_revenuerecon.sql` |
| `sales_invoice_lines` | `20260629000002_sprint5_sales.sql` | 1 | `20260629000002_sprint5_sales.sql` |
| `sales_invoices` | `20260629000002_sprint5_sales.sql` | 5 | `20260630000021_gap_fill.sql` |
| `sales_order_lines` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `sales_orders` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `sales_quotation_lines` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `sales_quotations` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `stock_adjustment_lines` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `stock_adjustments` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `stock_balances` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `stock_transfer_lines` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `stock_transfers` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `supplier_debit_memo_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `supplier_debit_memos` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `suppliers` | `20260628000003_sprint2.sql` | 2 | `20260701000014_supplier_atc_defaults.sql` |
| `sys_audit_logs` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `sys_feature_enablement` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `tax_calendar_events` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `tax_codes` | `20260628000003_sprint2.sql` | 2 | `20260628000004_fixes.sql` |
| `tax_credits_schedule` | `20260701000004_income_tax.sql` | 0 | `—` |
| `tax_detail_entries` | `20260629000019_hardening_v2.sql` | 3 | `20260701000016_pv_ewt_explicit_basis.sql` |
| `units_of_measure` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `user_company_memberships` | `20260629000008_rls_hardening.sql` | 2 | `20260630000021_gap_fill.sql` |
| `uses` | `20260630000021_gap_fill.sql` | 0 | `—` |
| `vat_codes` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `vat_returns` | `20260701000002_vat.sql` | 1 | `20260701000002_vat.sql` |
| `vendor_bill_lines` | `20260629000017_purchasing.sql` | 2 | `20260630000021_gap_fill.sql` |
| `vendor_bills` | `20260629000017_purchasing.sql` | 3 | `20260630000021_gap_fill.sql` |
| `vendor_credit_applications` | `20260629000019_hardening_v2.sql` | 3 | `20260701000011_vendor_credit_application_reversal.sql` |
| `vendor_credit_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `vendor_credits` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `void_reason_codes` | `20260629000002_sprint5_sales.sql` | 1 | `20260629000002_sprint5_sales.sql` |
| `warehouse_item_settings` | `20260630000029_master_data_completion.sql` | 1 | `20260630000029_master_data_completion.sql` |
| `warehouse_zones` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `warehouses` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |

## Triggers (141)

| Trigger | Latest definition |
| ------- | ----------------- |
| `approval_workflows_updated_at` | `20260628000002_sprint1.sql` |
| `atc_codes_updated_at` | `20260628000004_fixes.sql` |
| `bir_form_mappings_updated_at` | `20260628000005_sprint2_tax.sql` |
| `bir_forms_updated_at` | `20260628000005_sprint2_tax.sql` |
| `branches_updated_at` | `20260628000002_sprint1.sql` |
| `coa_updated_at` | `20260628000002_sprint1.sql` |
| `companies_updated_at` | `20260628000001_companies.sql` |
| `compliance_profiles_updated_at` | `20260628000005_sprint2_tax.sql` |
| `cost_centers_updated_at` | `20260628000002_sprint1.sql` |
| `customers_updated_at` | `20260628000003_sprint2.sql` |
| `departments_updated_at` | `20260628000002_sprint1.sql` |
| `ewt_codes_updated_at` | `20260628000003_sprint2.sql` |
| `feature_enablement_updated_at` | `20260628000002_sprint1.sql` |
| `fiscal_periods_updated_at` | `20260628000002_sprint1.sql` |
| `fiscal_years_updated_at` | `20260628000002_sprint1.sql` |
| `fwt_codes_updated_at` | `20260628000005_sprint2_tax.sql` |
| `item_categories_updated_at` | `20260628000003_sprint2.sql` |
| `items_updated_at` | `20260628000003_sprint2.sql` |
| `number_series_updated_at` | `20260628000002_sprint1.sql` |
| `payment_terms_updated_at` | `20260628000003_sprint2.sql` |
| `pt_codes_updated_at` | `20260628000005_sprint2_tax.sql` |
| `suppliers_updated_at` | `20260628000003_sprint2.sql` |
| `tax_calendar_events_updated_at` | `20260628000005_sprint2_tax.sql` |
| `tax_codes_updated_at` | `20260628000004_fixes.sql` |
| `trg_` | `20260701000004_income_tax.sql` |
| `trg_admin_lifecycle_journal_entries` | `20260702000010_can_perform_role_actions.sql` |
| `trg_admin_lifecycle_journal_entries_insert` | `20260702000010_can_perform_role_actions.sql` |
| `trg_admin_lifecycle_payment_vouchers` | `20260701000006_permissions_hardening.sql` |
| `trg_admin_lifecycle_payment_vouchers_insert` | `20260701000006_permissions_hardening.sql` |
| `trg_admin_lifecycle_petty_cash_vouchers` | `20260702000010_can_perform_role_actions.sql` |
| `trg_admin_lifecycle_petty_cash_vouchers_insert` | `20260702000010_can_perform_role_actions.sql` |
| `trg_admin_lifecycle_receipts` | `20260701000006_permissions_hardening.sql` |
| `trg_admin_lifecycle_receipts_insert` | `20260701000006_permissions_hardening.sql` |
| `trg_admin_lifecycle_sales_invoices` | `20260701000006_permissions_hardening.sql` |
| `trg_admin_lifecycle_sales_invoices_insert` | `20260701000006_permissions_hardening.sql` |
| `trg_admin_lifecycle_vendor_bills` | `20260701000006_permissions_hardening.sql` |
| `trg_admin_lifecycle_vendor_bills_insert` | `20260701000006_permissions_hardening.sql` |
| `trg_amort_sched_updated_at` | `20260630000026_amortization_revenuerecon.sql` |
| `trg_approval_sod_` | `20260703000001_approval_sod_enforcement.sql` |
| `trg_atc_code_history_guard` | `20260701000018_atc_effective_date_governance.sql` |
| `trg_audit_` | `20260701000005_audit_cas.sql` |
| `trg_audit_cash_purchases` | `20260630000021_gap_fill.sql` |
| `trg_audit_form_2307_issuance_lines` | `20260701000015_form2307_issued_generation_rpc.sql` |
| `trg_audit_form_2307_issuances` | `20260701000015_form2307_issued_generation_rpc.sql` |
| `trg_audit_payment_vouchers` | `20260630000021_gap_fill.sql` |
| `trg_audit_purchase_orders` | `20260630000021_gap_fill.sql` |
| `trg_audit_vendor_bills` | `20260630000021_gap_fill.sql` |
| `trg_audit_vendor_credits` | `20260630000021_gap_fill.sql` |
| `trg_bank_accounts_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_bank_adjustments_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_bank_reconciliations_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_block_pv_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` |
| `trg_block_receipt_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` |
| `trg_block_si_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` |
| `trg_block_vb_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` |
| `trg_cas_ar_updated_at` | `20260701000005_audit_cas.sql` |
| `trg_cash_count_sheets_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_check_vouchers_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_company_accounting_config_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_company_creator_owner` | `20260630000021_gap_fill.sql` |
| `trg_cp_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_cpl_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_credit_memo_lines_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_credit_memos_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_customer_cwt_default` | `20260701000017_customer_cwt_defaults.sql` |
| `trg_dashboard_layouts_updated_at` | `20260629000001_dashboard.sql` |
| `trg_dashboard_widgets_updated_at` | `20260629000001_dashboard.sql` |
| `trg_debit_memo_lines_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_debit_memos_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_dr_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_drl_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_emp_updated_at` | `20260630000029_master_data_completion.sql` |
| `trg_ewt_wp_headers_updated_at` | `20260629000006_ewt_working_papers.sql` |
| `trg_ewt_wp_lines_updated_at` | `20260629000006_ewt_working_papers.sql` |
| `trg_f2306_updated_at` | `20260701000003_withholding_tax.sql` |
| `trg_f2307_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_fa_updated_at` | `20260630000027_fixed_assets.sql` |
| `trg_fac_updated_at` | `20260630000027_fixed_assets.sql` |
| `trg_form2307_snapshot` | `20260703000005_report_snapshots_form2307.sql` |
| `trg_form2307_snapshot_guard` | `20260703000005_report_snapshots_form2307.sql` |
| `trg_form_2307_tracking_updated_at` | `20260629000007_cwt_2307.sql` |
| `trg_fund_transfers_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_generate_calendar_on_profile_change` | `20260628000005_sprint2_tax.sql` |
| `trg_gi_updated_at` | `20260630000028_inventory.sql` |
| `trg_inter_branch_transfers_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_journal_entries_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_journal_entry_lines_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_new_company_grant_access` | `20260630000021_gap_fill.sql` |
| `trg_new_user_grant_companies` | `20260630000021_gap_fill.sql` |
| `trg_payment_voucher_lines_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_payment_vouchers_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_pcs_updated_at` | `20260630000028_inventory.sql` |
| `trg_petty_cash_funds_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_petty_cash_replenishments_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_petty_cash_vouchers_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_po_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_pol_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_pr_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_prl_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_pt_returns_updated_at` | `20260701000001_percentage_tax.sql` |
| `trg_pt_wp_h_updated_at` | `20260701000001_percentage_tax.sql` |
| `trg_pv_ewt_ready_status` | `20260701000013_pv_ewt_atc_validation.sql` |
| `trg_pvl_ewt_validation` | `20260701000016_pv_ewt_explicit_basis.sql` |
| `trg_receipt_line_cwt_validation` | `20260701000017_customer_cwt_defaults.sql` |
| `trg_receipt_lines_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_receipts_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_rjt_updated_at` | `20260630000025_accounting_module.sql` |
| `trg_rr_sched_updated_at` | `20260630000026_amortization_revenuerecon.sql` |
| `trg_rr_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_rrl_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_sadj_updated_at` | `20260630000028_inventory.sql` |
| `trg_sales_invoice_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` |
| `trg_sdm_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_sdml_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_si_line_vat_registration` | `20260701000012_vat_registration_enforcement.sql` |
| `trg_si_updated_at` | `20260629000002_sprint5_sales.sql` |
| `trg_si_vat_registration_status` | `20260701000012_vat_registration_enforcement.sql` |
| `trg_sil_updated_at` | `20260629000002_sprint5_sales.sql` |
| `trg_so_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_sol_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_sq_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_sql_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_stx_updated_at` | `20260630000028_inventory.sql` |
| `trg_supplier_atc_default` | `20260701000014_supplier_atc_defaults.sql` |
| `trg_sync_number_series_shape` | `20260702000001_number_series_document_code_alignment.sql` |
| `trg_vat_return_snapshot` | `20260703000004_report_snapshots_vat_returns.sql` |
| `trg_vat_return_snapshot_guard` | `20260703000004_report_snapshots_vat_returns.sql` |
| `trg_vat_returns_registration` | `20260701000012_vat_registration_enforcement.sql` |
| `trg_vat_returns_status_reconciled` | `20260702000004_vat_ledger_gl_reconciliation.sql` |
| `trg_vat_returns_updated_at` | `20260701000002_vat.sql` |
| `trg_vat_wp_h_updated_at` | `20260701000002_vat.sql` |
| `trg_vb_line_vat_registration` | `20260701000012_vat_registration_enforcement.sql` |
| `trg_vb_vat_registration_status` | `20260701000012_vat_registration_enforcement.sql` |
| `trg_vc_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_vcl_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_vendor_bill_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` |
| `trg_vendor_bill_lines_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_vendor_bills_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_wh_updated_at` | `20260630000028_inventory.sql` |
| `trg_wis_updated_at` | `20260630000029_master_data_completion.sql` |
| `uom_updated_at` | `20260628000003_sprint2.sql` |
