# PXL Schema Summary

GENERATED FILE — do not hand-edit. Regenerate with `scripts/gen_schema_summary.sh` after adding migrations (CI does not enforce freshness; regenerate in any session that adds a migration).

Maps every database object to the migration holding its CURRENT definition, so agents do not grep the full chain. Column "Defs" counts how many migrations (re)define the object — a high count means the object has history worth checking before editing.

Generated: 2026-07-14. Migrations scanned: 110. Tests present: 51.

## Functions (266)

| Function | Latest definition | Defs |
| -------- | ----------------- | ---- |
| `can_admin_company` | `20260701000006_permissions_hardening.sql` | 3 |
| `fn_abandon_document_number` | `20260710000005_cas_numbering_void_dat_controls.sql` | 1 |
| `fn_acknowledge_supplier_debit_memo` | `20260630000021_gap_fill.sql` | 2 |
| `fn_add_cost_layer` | `20260630000028_inventory.sql` | 1 |
| `fn_add_posting_line` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_add_tax_detail` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_ap_aging_asof` | `20260713000010_withholding_basis_policy.sql` | 2 |
| `fn_ap_subledger_gl_reconciliation_asof` | `20260714000008_da013_asof_ledger_reconciliation.sql` | 1 |
| `fn_apply_cash_purchase_line_ewt_profile` | `20260713000015_cash_purchase_ewt.sql` | 1 |
| `fn_apply_vendor_bill_line_ewt_profile` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_apply_vendor_credit` | `20260701000011_vendor_credit_application_reversal.sql` | 4 |
| `fn_approve_petty_cash_voucher` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_approve_purchase_order` | `20260630000021_gap_fill.sql` | 2 |
| `fn_approve_sales_invoice` | `20260701000008_accounting_readiness_approval.sql` | 3 |
| `fn_approve_vendor_bill` | `20260701000008_accounting_readiness_approval.sql` | 3 |
| `fn_ar_aging_asof` | `20260702000003_ar_ap_aging_asof_rpcs.sql` | 1 |
| `fn_ar_subledger_gl_reconciliation_asof` | `20260714000008_da013_asof_ledger_reconciliation.sql` | 1 |
| `fn_assert_posting_source` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_assert_source_journal_link` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_atc_code_is_current` | `20260701000018_atc_effective_date_governance.sql` | 1 |
| `fn_atc_code_used` | `20260714000003_withholding_master_consolidation.sql` | 4 |
| `fn_atc_last_document_date` | `20260710000004_atc_document_date_versioning.sql` | 1 |
| `fn_atc_version_asof` | `20260713000002_atc_document_date_versioning.sql` | 1 |
| `fn_audit_trigger` | `20260630000021_gap_fill.sql` | 2 |
| `fn_begin_source_posting` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_bind_cas_document_number` | `20260712000004_cas_numbering_void_evidence.sql` | 1 |
| `fn_block_pv_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_block_receipt_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_block_si_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_block_vb_line_mutation_after_draft` | `20260701000009_core_line_immutability.sql` | 1 |
| `fn_books_export_reconciliation` | `20260713000009_books_reconciliation_audit_package.sql` | 1 |
| `fn_bounce_receipt` | `20260714000005_form2307_received_claim_lifecycle.sql` | 6 |
| `fn_bt_reverse_je` | `20260711000001_posting_engine_completion.sql` | 3 |
| `fn_can_perform` | `20260702000010_can_perform_role_actions.sql` | 1 |
| `fn_cancel_amortization_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_cancel_bank_adjustment` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_check_voucher` | `20260711000001_posting_engine_completion.sql` | 3 |
| `fn_cancel_fund_transfer` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_inter_branch_transfer` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_payment_voucher` | `20260711000001_posting_engine_completion.sql` | 4 |
| `fn_cancel_petty_cash_voucher` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `fn_cancel_purchase_order` | `20260630000021_gap_fill.sql` | 2 |
| `fn_cancel_revenue_recognition_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_capture_approval_instance_event` | `20260713000014_transaction_events.sql` | 1 |
| `fn_capture_cas_document_void` | `20260712000004_cas_numbering_void_evidence.sql` | 2 |
| `fn_capture_journal_entry_event` | `20260713000014_transaction_events.sql` | 1 |
| `fn_capture_registered_source_event` | `20260713000014_transaction_events.sql` | 1 |
| `fn_capture_report_snapshot_event` | `20260713000014_transaction_events.sql` | 1 |
| `fn_claim_form2307_received` | `20260714000005_form2307_received_claim_lifecycle.sql` | 1 |
| `fn_close_fiscal_year` | `20260713000013_je_classification_and_close.sql` | 1 |
| `fn_company_ap_ewt_policy` | `20260713000010_withholding_basis_policy.sql` | 1 |
| `fn_company_ewt_payable_enabled` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_company_twa_auto_ewt_enabled` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_complete_purchase_return` | `20260711000001_posting_engine_completion.sql` | 4 |
| `fn_complete_purchase_return_source_locked_impl` | `20260712000003_posting_runtime_repairs.sql` | 1 |
| `fn_complete_secondary_posting` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_compute_depr_schedule` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_compute_ewt_remitted_prior` | `20260713000005_withholding_remittance_flow.sql` | 1 |
| `fn_compute_ewt_return` | `20260710000001_ewt_return_reconciliation_gate.sql` | 1 |
| `fn_confirm_receiving_report` | `20260630000021_gap_fill.sql` | 2 |
| `fn_consume_cost_layers` | `20260630000028_inventory.sql` | 1 |
| `fn_create_amortization_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_create_posted_journal_entry` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_create_revenue_recognition_schedule` | `20260630000026_amortization_revenuerecon.sql` | 1 |
| `fn_customer_ledger_asof` | `20260714000008_da013_asof_ledger_reconciliation.sql` | 1 |
| `fn_default_ap_supplier_tin_snapshot` | `20260714000007_aud009_aud010_accounting_readiness_closure.sql` | 1 |
| `fn_dispose_fixed_asset` | `20260712000002_aud051_numbering_registry_alignment.sql` | 2 |
| `fn_enforce_approval_sod` | `20260703000001_approval_sod_enforcement.sql` | 1 |
| `fn_enforce_atc_version_rules` | `20260713000002_atc_document_date_versioning.sql` | 1 |
| `fn_enforce_atc_version_window` | `20260710000004_atc_document_date_versioning.sql` | 1 |
| `fn_enforce_journal_entry_balanced` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_enforce_journal_entry_source` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_enforce_tax_code_version_rules` | `20260713000012_tax_code_effective_date_governance.sql` | 1 |
| `fn_ensure_stock_balance` | `20260630000028_inventory.sql` | 1 |
| `fn_execute_recurring_template` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_export_csv_line` | `20260713000007_cas_export_file_hashes.sql` | 1 |
| `fn_export_dat_cell` | `20260713000008_cas_dat_layout.sql` | 1 |
| `fn_export_dat_file_name` | `20260713000008_cas_dat_layout.sql` | 1 |
| `fn_export_dat_numeric` | `20260713000008_cas_dat_layout.sql` | 1 |
| `fn_export_dat_tin` | `20260713000008_cas_dat_layout.sql` | 1 |
| `fn_export_decimal` | `20260713000007_cas_export_file_hashes.sql` | 1 |
| `fn_finalize_journal_entry` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_flag_form2307_issued_for_ewt_reversal` | `20260714000005_form2307_received_claim_lifecycle.sql` | 1 |
| `fn_forbid_cas_void_evidence_change` | `20260712000004_cas_numbering_void_evidence.sql` | 1 |
| `fn_form2307_period_bounds` | `20260703000005_report_snapshots_form2307.sql` | 1 |
| `fn_form2307_report_payload` | `20260714000005_form2307_received_claim_lifecycle.sql` | 2 |
| `fn_generate_form_2307_issued` | `20260714000002_form2307_monthly_breakdown.sql` | 4 |
| `fn_generate_tax_calendar` | `20260628000005_sprint2_tax.sql` | 1 |
| `fn_generate_tax_calendar_trigger` | `20260628000005_sprint2_tax.sql` | 1 |
| `fn_get_accounting_trace` | `20260711000002_accounting_trace_reports.sql` | 2 |
| `fn_get_report_snapshot_trace_links` | `20260711000002_accounting_trace_reports.sql` | 1 |
| `fn_get_report_trace_set` | `20260714000006_aud049_withholding_trace_drilldowns.sql` | 2 |
| `fn_gl_impact_payload` | `20260714000001_advance_payment_withholding.sql` | 2 |
| `fn_grant_all_users_on_new_company` | `20260630000021_gap_fill.sql` | 2 |
| `fn_grant_creator_company_ownership` | `20260630000021_gap_fill.sql` | 2 |
| `fn_grant_new_user_all_companies` | `20260630000021_gap_fill.sql` | 2 |
| `fn_guard_atc_code_history` | `20260713000002_atc_document_date_versioning.sql` | 3 |
| `fn_guard_cas_number_series` | `20260712000004_cas_numbering_void_evidence.sql` | 1 |
| `fn_guard_doc_header` | `20260704000002_status_immutability.sql` | 1 |
| `fn_guard_doc_lines` | `20260704000002_status_immutability.sql` | 1 |
| `fn_guard_form2307_received_tracking` | `20260714000005_form2307_received_claim_lifecycle.sql` | 1 |
| `fn_guard_form2307_snapshot_immutable` | `20260703000005_report_snapshots_form2307.sql` | 1 |
| `fn_guard_journal_entry_line` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_guard_journal_entry_posting` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_guard_tax_code_history` | `20260713000012_tax_code_effective_date_governance.sql` | 1 |
| `fn_guard_vat_code_history` | `20260713000012_tax_code_effective_date_governance.sql` | 1 |
| `fn_guard_vat_return_snapshot_immutable` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_invalidate_form2307_received_for_receipt` | `20260714000005_form2307_received_claim_lifecycle.sql` | 1 |
| `fn_je_dimensions_guard` | `20260704000001_je_line_dimensions.sql` | 1 |
| `fn_je_line_dimensions_guard` | `20260704000001_je_line_dimensions.sql` | 1 |
| `fn_link_cas_document_number` | `20260710000005_cas_numbering_void_dat_controls.sql` | 1 |
| `fn_link_fixed_asset_journal_source` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_link_purchase_return_journal_source` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_link_schedule_journal_source` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_lock_unwrapped_posting_source` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_mark_tax_event_filed` | `20260630000021_gap_fill.sql` | 2 |
| `fn_next_document_number` | `20260712000004_cas_numbering_void_evidence.sql` | 5 |
| `fn_normalize_report_source_type` | `20260711000002_accounting_trace_reports.sql` | 1 |
| `fn_post_amortization_entry` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_bank_adjustment` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_cash_purchase` | `20260711000001_posting_engine_completion.sql` | 5 |
| `fn_post_cash_purchase_source_locked_impl` | `20260713000015_cash_purchase_ewt.sql` | 1 |
| `fn_post_check_voucher` | `20260713000002_atc_document_date_versioning.sql` | 4 |
| `fn_post_credit_memo` | `20260711000001_posting_engine_completion.sql` | 5 |
| `fn_post_debit_memo` | `20260711000001_posting_engine_completion.sql` | 5 |
| `fn_post_depreciation_entry` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_depreciation_entry_source_locked_impl` | `20260712000002_aud051_numbering_registry_alignment.sql` | 1 |
| `fn_post_fund_transfer` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_goods_issue` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_goods_issue_source_locked_impl` | `20260712000002_aud051_numbering_registry_alignment.sql` | 1 |
| `fn_post_inter_branch_transfer` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_manual_je` | `20260713000013_je_classification_and_close.sql` | 3 |
| `fn_post_payment_voucher` | `20260714000001_advance_payment_withholding.sql` | 8 |
| `fn_post_petty_cash_replenishment` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_physical_count` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_physical_count_source_locked_impl` | `20260712000003_posting_runtime_repairs.sql` | 2 |
| `fn_post_receipt` | `20260714000001_advance_payment_withholding.sql` | 8 |
| `fn_post_revenue_recognition_entry` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_sales_invoice` | `20260711000001_posting_engine_completion.sql` | 7 |
| `fn_post_stock_adjustment` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_stock_adjustment_source_locked_impl` | `20260712000002_aud051_numbering_registry_alignment.sql` | 1 |
| `fn_post_stock_transfer` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_post_stock_transfer_source_locked_impl` | `20260712000003_posting_runtime_repairs.sql` | 2 |
| `fn_post_vendor_bill` | `20260713000010_withholding_basis_policy.sql` | 6 |
| `fn_post_vendor_credit` | `20260711000001_posting_engine_completion.sql` | 6 |
| `fn_post_withholding_remittance` | `20260713000005_withholding_remittance_flow.sql` | 1 |
| `fn_preview_gl_impact` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_qap_2307_reconciliation` | `20260713000006_qap_multi_atc_reconciliation.sql` | 1 |
| `fn_rebuild_document_vat_details` | `20260710000002_vat_registration_all_documents.sql` | 1 |
| `fn_receive_inventory` | `20260630000028_inventory.sql` | 1 |
| `fn_record_form2307_received` | `20260714000005_form2307_received_claim_lifecycle.sql` | 1 |
| `fn_record_impairment` | `20260712000002_aud051_numbering_registry_alignment.sql` | 2 |
| `fn_record_posting_event` | `20260713000014_transaction_events.sql` | 2 |
| `fn_record_transaction_event` | `20260713000014_transaction_events.sql` | 1 |
| `fn_register_fixed_asset` | `20260712000002_aud051_numbering_registry_alignment.sql` | 2 |
| `fn_render_cas_dat` | `20260713000008_cas_dat_layout.sql` | 2 |
| `fn_render_cas_dat_text` | `20260713000008_cas_dat_layout.sql` | 1 |
| `fn_report_snapshot_key_uuid` | `20260703000006_report_snapshots_vat_exports.sql` | 1 |
| `fn_require_admin_for_accounting_lifecycle` | `20260702000010_can_perform_role_actions.sql` | 3 |
| `fn_require_cas_reversal_reason` | `20260710000005_cas_numbering_void_dat_controls.sql` | 1 |
| `fn_require_cash_purchase_post_ewt_profile` | `20260713000015_cash_purchase_ewt.sql` | 1 |
| `fn_require_check_voucher_post_ewt_profile` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_require_company_ewt_payable_enabled` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_require_customer_cwt_default` | `20260701000018_atc_effective_date_governance.sql` | 2 |
| `fn_require_cv_ewt_validation` | `20260713000011_withholding_profile_gates.sql` | 4 |
| `fn_require_document_header_vat_registration` | `20260710000002_vat_registration_all_documents.sql` | 1 |
| `fn_require_document_line_vat_registration` | `20260710000002_vat_registration_all_documents.sql` | 1 |
| `fn_require_ewt_return_profile` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_require_ewt_return_reconciled` | `20260713000005_withholding_remittance_flow.sql` | 2 |
| `fn_require_open_fiscal_period` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_require_payment_voucher_post_ewt_profile` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_require_postable_account` | `20260710000003_posting_engine_preview_trace.sql` | 1 |
| `fn_require_pv_ewt_ready_status` | `20260701000013_pv_ewt_atc_validation.sql` | 1 |
| `fn_require_pvl_ewt_validation` | `20260713000011_withholding_profile_gates.sql` | 6 |
| `fn_require_receipt_line_cwt_validation` | `20260713000002_atc_document_date_versioning.sql` | 4 |
| `fn_require_si_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` | 1 |
| `fn_require_si_line_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_si_vat_registration_status` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vat_export_snapshot_registration` | `20260710000002_vat_registration_all_documents.sql` | 1 |
| `fn_require_vat_registered_company` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vat_return_reconciled` | `20260702000004_vat_ledger_gl_reconciliation.sql` | 1 |
| `fn_require_vat_return_registered_company` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vb_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` | 1 |
| `fn_require_vb_line_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vb_vat_registration_status` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_require_vendor_bill_post_ewt_profile` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_require_wht_export_profile` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_required_approval_workflow` | `20260703000001_approval_sod_enforcement.sql` | 1 |
| `fn_reserve_document_number` | `20260710000005_cas_numbering_void_dat_controls.sql` | 1 |
| `fn_resolve_posting_source` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_reverse_je` | `20260711000001_posting_engine_completion.sql` | 3 |
| `fn_reverse_posted_journal_entry` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_reverse_tax_detail_entries` | `20260711000001_posting_engine_completion.sql` | 2 |
| `fn_reverse_vendor_credit_application` | `20260701000011_vendor_credit_application_reversal.sql` | 1 |
| `fn_revert_si_to_draft` | `20260630000021_gap_fill.sql` | 2 |
| `fn_revert_vendor_bill_to_draft` | `20260630000021_gap_fill.sql` | 2 |
| `fn_row_written_by_current_txn` | `20260704000002_status_immutability.sql` | 1 |
| `fn_save_cash_purchase` | `20260713000015_cash_purchase_ewt.sql` | 3 |
| `fn_save_cash_sale` | `20260704000003_receipt_cwt_explicit_base.sql` | 5 |
| `fn_save_credit_memo` | `20260630000022_tax_ledger_completeness.sql` | 4 |
| `fn_save_debit_memo` | `20260630000022_tax_ledger_completeness.sql` | 4 |
| `fn_save_payment_voucher` | `20260714000001_advance_payment_withholding.sql` | 9 |
| `fn_save_purchase_order` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_purchase_return` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_receipt` | `20260714000001_advance_payment_withholding.sql` | 10 |
| `fn_save_receiving_report` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_sales_invoice` | `20260630000021_gap_fill.sql` | 3 |
| `fn_save_supplier_debit_memo` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_vendor_bill` | `20260713000010_withholding_basis_policy.sql` | 4 |
| `fn_save_vendor_credit` | `20260630000021_gap_fill.sql` | 2 |
| `fn_save_withholding_remittance` | `20260713000005_withholding_remittance_flow.sql` | 1 |
| `fn_send_supplier_debit_memo` | `20260630000021_gap_fill.sql` | 2 |
| `fn_set_updated_at` | `20260629000001_dashboard.sql` | 1 |
| `fn_ship_purchase_return` | `20260630000021_gap_fill.sql` | 2 |
| `fn_snapshot_books_export` | `20260713000009_books_reconciliation_audit_package.sql` | 3 |
| `fn_snapshot_cas_audit_package` | `20260713000009_books_reconciliation_audit_package.sql` | 2 |
| `fn_snapshot_cas_export` | `20260710000002_vat_registration_all_documents.sql` | 2 |
| `fn_snapshot_cas_export_unchecked` | `20260713000008_cas_dat_layout.sql` | 2 |
| `fn_snapshot_form2307_issued` | `20260714000002_form2307_monthly_breakdown.sql` | 2 |
| `fn_snapshot_vat_export` | `20260710000002_vat_registration_all_documents.sql` | 2 |
| `fn_snapshot_vat_return` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_snapshot_wht_export` | `20260713000006_qap_multi_atc_reconciliation.sql` | 3 |
| `fn_supersede_form_2307_issued` | `20260714000002_form2307_monthly_breakdown.sql` | 2 |
| `fn_supplier_ledger_asof` | `20260714000008_da013_asof_ledger_reconciliation.sql` | 1 |
| `fn_sync_number_series_shape` | `20260702000001_number_series_document_code_alignment.sql` | 1 |
| `fn_sync_receipt_totals_from_lines` | `20260714000004_cash_sale_receipt_total_semantics.sql` | 1 |
| `fn_sync_vendor_bill_ewt_expected` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_tax_code_is_current` | `20260713000012_tax_code_effective_date_governance.sql` | 1 |
| `fn_tax_code_used` | `20260713000012_tax_code_effective_date_governance.sql` | 1 |
| `fn_tax_code_version_asof` | `20260713000012_tax_code_effective_date_governance.sql` | 1 |
| `fn_transaction_actor_role` | `20260713000014_transaction_events.sql` | 1 |
| `fn_transaction_event_type_for_status` | `20260713000014_transaction_events.sql` | 1 |
| `fn_transfer_fixed_asset` | `20260630000027_fixed_assets.sql` | 1 |
| `fn_twa_ewt_atc_asof` | `20260713000011_withholding_profile_gates.sql` | 1 |
| `fn_update_form_2307_issued_status` | `20260701000015_form2307_issued_generation_rpc.sql` | 1 |
| `fn_update_payment_tracking` | `20260630000021_gap_fill.sql` | 2 |
| `fn_update_wac` | `20260630000028_inventory.sql` | 1 |
| `fn_validate_cash_purchase_ewt_ready` | `20260713000015_cash_purchase_ewt.sql` | 1 |
| `fn_validate_company_vat_amount` | `20260710000002_vat_registration_all_documents.sql` | 1 |
| `fn_validate_company_vat_code` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_validate_document_vat_registration` | `20260710000002_vat_registration_all_documents.sql` | 1 |
| `fn_validate_form2307_received_tracking` | `20260714000005_form2307_received_claim_lifecycle.sql` | 1 |
| `fn_validate_invoice_posting_totals` | `20260711000001_posting_engine_completion.sql` | 1 |
| `fn_validate_payment_voucher_ewt_ready` | `20260714000007_aud009_aud010_accounting_readiness_closure.sql` | 8 |
| `fn_validate_payment_voucher_line_ewt` | `20260713000002_atc_document_date_versioning.sql` | 5 |
| `fn_validate_receipt_cwt_ready` | `20260713000003_settlement_total_line_authority.sql` | 5 |
| `fn_validate_receipt_line_cwt` | `20260713000002_atc_document_date_versioning.sql` | 5 |
| `fn_validate_sales_invoice_accounting_ready` | `20260701000008_accounting_readiness_approval.sql` | 1 |
| `fn_validate_sales_invoice_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_validate_settlement_posting` | `20260714000001_advance_payment_withholding.sql` | 3 |
| `fn_validate_supplier_atc_default` | `20260701000018_atc_effective_date_governance.sql` | 2 |
| `fn_validate_vendor_bill_accounting_ready` | `20260714000007_aud009_aud010_accounting_readiness_closure.sql` | 2 |
| `fn_validate_vendor_bill_vat_registration` | `20260701000012_vat_registration_enforcement.sql` | 1 |
| `fn_vat_code_used` | `20260713000012_tax_code_effective_date_governance.sql` | 1 |
| `fn_vat_gl_reconciliation` | `20260702000005_gl_reversal_visibility.sql` | 2 |
| `fn_vat_return_period_bounds` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_vat_return_report_payload` | `20260703000004_report_snapshots_vat_returns.sql` | 1 |
| `fn_vendor_bill_accrued_ewt_amount` | `20260713000010_withholding_basis_policy.sql` | 1 |
| `fn_vendor_bill_has_accrued_ewt` | `20260713000010_withholding_basis_policy.sql` | 1 |
| `fn_void_sales_invoice` | `20260711000001_posting_engine_completion.sql` | 5 |
| `fn_void_vendor_bill` | `20260711000001_posting_engine_completion.sql` | 5 |
| `fn_void_withholding_remittance` | `20260713000005_withholding_remittance_flow.sql` | 1 |
| `fn_wht_gl_reconciliation` | `20260713000005_withholding_remittance_flow.sql` | 2 |
| `is_any_company_admin` | `20260630000021_gap_fill.sql` | 2 |
| `is_company_member` | `20260630000021_gap_fill.sql` | 2 |
| `update_updated_at` | `20260628000001_companies.sql` | 1 |

## Views (20)

| View | Latest definition | Defs |
| ---- | ----------------- | ---- |
| `vw_ap_aging` | `20260630000021_gap_fill.sql` | 2 |
| `vw_cas_atp_usage` | `20260712000004_cas_numbering_void_evidence.sql` | 2 |
| `vw_credit_memo_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_customer_ledger` | `20260711000002_accounting_trace_reports.sql` | 4 |
| `vw_cwt_summary_ar` | `20260711000002_accounting_trace_reports.sql` | 2 |
| `vw_debit_memo_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_deposits_in_transit` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `vw_ewt_summary_ap` | `20260711000002_accounting_trace_reports.sql` | 6 |
| `vw_general_ledger` | `20260713000013_je_classification_and_close.sql` | 4 |
| `vw_input_vat_review` | `20260711000002_accounting_trace_reports.sql` | 5 |
| `vw_output_vat_review` | `20260711000002_accounting_trace_reports.sql` | 3 |
| `vw_outstanding_checks` | `20260630000024_banking_treasury_functions.sql` | 1 |
| `vw_payment_register` | `20260630000021_gap_fill.sql` | 2 |
| `vw_receipt_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_sales_invoice_register` | `20260629000005_sprint5_views.sql` | 1 |
| `vw_sdm_register` | `20260630000021_gap_fill.sql` | 2 |
| `vw_slp_export` | `20260630000021_gap_fill.sql` | 2 |
| `vw_supplier_ledger` | `20260711000002_accounting_trace_reports.sql` | 3 |
| `vw_trial_balance` | `20260702000005_gl_reversal_visibility.sql` | 2 |
| `vw_vendor_bill_register` | `20260630000021_gap_fill.sql` | 2 |

## Tables (149)

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
| `atc_codes` | `20260628000003_sprint2.sql` | 7 | `20260713000002_atc_document_date_versioning.sql` |
| `bank_accounts` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bank_adjustments` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bank_recon_items` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bank_reconciliations` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `bir_form_mappings` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `bir_forms` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `book_tax_reconciliation` | `20260701000004_income_tax.sql` | 0 | `—` |
| `branches` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `cas_attachment_register` | `20260701000005_audit_cas.sql` | 1 | `20260701000005_audit_cas.sql` |
| `cas_document_number_issuances` | `20260710000005_cas_numbering_void_dat_controls.sql` | 2 | `20260712000004_cas_numbering_void_evidence.sql` |
| `cas_document_void_events` | `20260710000005_cas_numbering_void_dat_controls.sql` | 2 | `20260712000004_cas_numbering_void_evidence.sql` |
| `cas_export_artifacts` | `20260710000005_cas_numbering_void_dat_controls.sql` | 2 | `20260713000008_cas_dat_layout.sql` |
| `cas_export_log` | `20260701000005_audit_cas.sql` | 5 | `20260713000008_cas_dat_layout.sql` |
| `cash_count_sheets` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `cash_purchase_lines` | `20260629000018_purchasing_full.sql` | 3 | `20260713000015_cash_purchase_ewt.sql` |
| `cash_purchases` | `20260629000018_purchasing_full.sql` | 3 | `20260713000015_cash_purchase_ewt.sql` |
| `chart_of_accounts` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `check_voucher_lines` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `check_vouchers` | `20260630000023_banking_treasury_schema.sql` | 2 | `20260705000001_cv_ewt_supplier_validation.sql` |
| `companies` | `20260628000001_companies.sql` | 3 | `20260713000010_withholding_basis_policy.sql` |
| `company_accounting_config` | `20260629000013_gl_core.sql` | 4 | `20260714000001_advance_payment_withholding.sql` |
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
| `customers` | `20260628000003_sprint2.sql` | 4 | `20260714000003_withholding_master_consolidation.sql` |
| `dashboard_layouts` | `20260629000001_dashboard.sql` | 1 | `20260629000001_dashboard.sql` |
| `dashboard_widgets` | `20260629000001_dashboard.sql` | 1 | `20260629000001_dashboard.sql` |
| `debit_memo_lines` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `debit_memos` | `20260629000003_sprint5_ar.sql` | 4 | `20260630000022_tax_ledger_completeness.sql` |
| `delivery_receipt_lines` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `delivery_receipts` | `20260629000004_sprint5_so_dr.sql` | 1 | `20260629000004_sprint5_so_dr.sql` |
| `departments` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `employees` | `20260630000029_master_data_completion.sql` | 1 | `20260630000029_master_data_completion.sql` |
| `ewt_returns` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `exchange_rates` | `20260628000002_sprint1.sql` | 2 | `20260628000004_fixes.sql` |
| `fiscal_periods` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `fiscal_years` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `fixed_asset_categories` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `fixed_assets` | `20260630000027_fixed_assets.sql` | 1 | `20260630000027_fixed_assets.sql` |
| `form_2306_issuances` | `20260701000003_withholding_tax.sql` | 1 | `20260701000003_withholding_tax.sql` |
| `form_2307_issuance_lines` | `20260630000022_tax_ledger_completeness.sql` | 2 | `20260714000002_form2307_monthly_breakdown.sql` |
| `form_2307_issuances` | `20260629000018_purchasing_full.sql` | 4 | `20260714000005_form2307_received_claim_lifecycle.sql` |
| `form_2307_tracking` | `20260629000007_cwt_2307.sql` | 4 | `20260714000005_form2307_received_claim_lifecycle.sql` |
| `fund_transfers` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `fwt_returns` | `20260701000003_withholding_tax.sql` | 0 | `—` |
| `goods_issue_lines` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `goods_issues` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `income_tax_computations` | `20260701000004_income_tax.sql` | 0 | `—` |
| `inter_branch_transfers` | `20260630000023_banking_treasury_schema.sql` | 1 | `20260630000023_banking_treasury_schema.sql` |
| `inventory_cost_layers` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `inventory_transactions` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `item_categories` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `items` | `20260628000003_sprint2.sql` | 2 | `20260714000003_withholding_master_consolidation.sql` |
| `itr_filings` | `20260701000004_income_tax.sql` | 0 | `—` |
| `journal_entries` | `20260629000013_gl_core.sql` | 7 | `20260713000013_je_classification_and_close.sql` |
| `journal_entry_lines` | `20260629000013_gl_core.sql` | 3 | `20260704000001_je_line_dimensions.sql` |
| `mcit_computations` | `20260701000004_income_tax.sql` | 0 | `—` |
| `nolco_schedule` | `20260701000004_income_tax.sql` | 0 | `—` |
| `number_series` | `20260628000002_sprint1.sql` | 2 | `20260702000001_number_series_document_code_alignment.sql` |
| `payment_terms` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `payment_voucher_lines` | `20260629000017_purchasing.sql` | 4 | `20260714000001_advance_payment_withholding.sql` |
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
| `receipt_lines` | `20260629000003_sprint5_ar.sql` | 6 | `20260714000001_advance_payment_withholding.sql` |
| `receipts` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `receiving_report_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `receiving_reports` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `recurring_journal_template_lines` | `20260630000025_accounting_module.sql` | 1 | `20260630000025_accounting_module.sql` |
| `recurring_journal_templates` | `20260630000025_accounting_module.sql` | 1 | `20260630000025_accounting_module.sql` |
| `ref_compliance_forms` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `ref_document_types` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `ref_feature_definitions` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `ref_payment_modes` | `20260629000003_sprint5_ar.sql` | 1 | `20260629000003_sprint5_ar.sql` |
| `ref_posting_source_types` | `20260710000003_posting_engine_preview_trace.sql` | 1 | `20260710000003_posting_engine_preview_trace.sql` |
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
| `suppliers` | `20260628000003_sprint2.sql` | 3 | `20260714000003_withholding_master_consolidation.sql` |
| `sys_audit_logs` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `sys_feature_enablement` | `20260628000002_sprint1.sql` | 1 | `20260628000002_sprint1.sql` |
| `tax_calendar_events` | `20260628000005_sprint2_tax.sql` | 1 | `20260628000005_sprint2_tax.sql` |
| `tax_codes` | `20260628000003_sprint2.sql` | 3 | `20260713000012_tax_code_effective_date_governance.sql` |
| `tax_credits_schedule` | `20260701000004_income_tax.sql` | 0 | `—` |
| `tax_detail_entries` | `20260629000019_hardening_v2.sql` | 4 | `20260711000001_posting_engine_completion.sql` |
| `transaction_events` | `20260713000014_transaction_events.sql` | 1 | `20260713000014_transaction_events.sql` |
| `units_of_measure` | `20260628000003_sprint2.sql` | 1 | `20260628000003_sprint2.sql` |
| `user_company_memberships` | `20260629000008_rls_hardening.sql` | 2 | `20260630000021_gap_fill.sql` |
| `uses` | `20260630000021_gap_fill.sql` | 0 | `—` |
| `vat_codes` | `20260628000003_sprint2.sql` | 2 | `20260713000012_tax_code_effective_date_governance.sql` |
| `vat_returns` | `20260701000002_vat.sql` | 1 | `20260701000002_vat.sql` |
| `vendor_bill_lines` | `20260629000017_purchasing.sql` | 3 | `20260713000010_withholding_basis_policy.sql` |
| `vendor_bills` | `20260629000017_purchasing.sql` | 4 | `20260712000003_posting_runtime_repairs.sql` |
| `vendor_credit_applications` | `20260629000019_hardening_v2.sql` | 3 | `20260701000011_vendor_credit_application_reversal.sql` |
| `vendor_credit_lines` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `vendor_credits` | `20260629000018_purchasing_full.sql` | 2 | `20260630000021_gap_fill.sql` |
| `void_reason_codes` | `20260629000002_sprint5_sales.sql` | 1 | `20260629000002_sprint5_sales.sql` |
| `warehouse_item_settings` | `20260630000029_master_data_completion.sql` | 1 | `20260630000029_master_data_completion.sql` |
| `warehouse_zones` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `warehouses` | `20260630000028_inventory.sql` | 1 | `20260630000028_inventory.sql` |
| `withholding_remittances` | `20260713000005_withholding_remittance_flow.sql` | 1 | `20260713000005_withholding_remittance_flow.sql` |

## Triggers (287)

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
| `feature_enablement_updated_at` | `20260628000002_sprint1.sql` |
| `fiscal_periods_updated_at` | `20260628000002_sprint1.sql` |
| `fiscal_years_updated_at` | `20260628000002_sprint1.sql` |
| `item_categories_updated_at` | `20260628000003_sprint2.sql` |
| `items_updated_at` | `20260628000003_sprint2.sql` |
| `number_series_updated_at` | `20260628000002_sprint1.sql` |
| `payment_terms_updated_at` | `20260628000003_sprint2.sql` |
| `pt_codes_updated_at` | `20260628000005_sprint2_tax.sql` |
| `suppliers_updated_at` | `20260628000003_sprint2.sql` |
| `tax_calendar_events_updated_at` | `20260628000005_sprint2_tax.sql` |
| `tax_codes_updated_at` | `20260628000004_fixes.sql` |
| `trg_` | `20260701000003_withholding_tax.sql` |
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
| `trg_atc_code_history_guard` | `20260701000018_atc_effective_date_governance.sql` |
| `trg_atc_version_rules` | `20260713000002_atc_document_date_versioning.sql` |
| `trg_atc_version_window` | `20260710000004_atc_document_date_versioning.sql` |
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
| `trg_cas_number_bank_adjustments` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_cash_count_sheets` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_cash_purchases` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_check_vouchers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_credit_memos` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_debit_memos` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_delivery_receipts` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_fund_transfers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_inter_branch_transfers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_journal_entries` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_payment_vouchers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_petty_cash_replenishments` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_petty_cash_vouchers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_purchase_orders` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_receipts` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_receiving_reports` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_sales_invoices` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_sales_orders` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_sales_quotations` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_vendor_bills` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_number_vendor_credits` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_bank_adjustments` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_check_vouchers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_credit_memos` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_debit_memos` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_fund_transfers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_inter_branch_transfers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_payment_vouchers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_petty_cash_vouchers` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_receipts` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_sales_invoices` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_vendor_bills` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cas_void_vendor_credits` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_cash_count_sheets_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_cash_purchase_post_ewt_profile` | `20260713000015_cash_purchase_ewt.sql` |
| `trg_check_voucher_post_ewt_profile` | `20260713000011_withholding_profile_gates.sql` |
| `trg_check_vouchers_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_cm_line_vat_registration` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_cm_vat_registration_status` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_company_accounting_config_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_company_creator_owner` | `20260630000021_gap_fill.sql` |
| `trg_cp_line_vat_registration` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_cp_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_cp_vat_registration_status` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_cpl_ewt_profile` | `20260713000015_cash_purchase_ewt.sql` |
| `trg_cpl_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_credit_memo_lines_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_credit_memos_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_customer_cwt_default` | `20260701000017_customer_cwt_defaults.sql` |
| `trg_cv_ewt_validation` | `20260713000011_withholding_profile_gates.sql` |
| `trg_dashboard_layouts_updated_at` | `20260629000001_dashboard.sql` |
| `trg_dashboard_widgets_updated_at` | `20260629000001_dashboard.sql` |
| `trg_debit_memo_lines_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_debit_memos_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_default_payment_voucher_supplier_tin_snapshot` | `20260714000007_aud009_aud010_accounting_readiness_closure.sql` |
| `trg_default_vendor_bill_supplier_tin_snapshot` | `20260714000007_aud009_aud010_accounting_readiness_closure.sql` |
| `trg_dm_line_vat_registration` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_dm_vat_registration_status` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_dr_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_drl_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_emp_updated_at` | `20260630000029_master_data_completion.sql` |
| `trg_ewt_return_profile` | `20260713000011_withholding_profile_gates.sql` |
| `trg_ewt_returns_status_reconciled` | `20260710000001_ewt_return_reconciliation_gate.sql` |
| `trg_ewt_wp_headers_updated_at` | `20260629000006_ewt_working_papers.sql` |
| `trg_ewt_wp_lines_updated_at` | `20260629000006_ewt_working_papers.sql` |
| `trg_f2306_updated_at` | `20260701000003_withholding_tax.sql` |
| `trg_f2307_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_fa_updated_at` | `20260630000027_fixed_assets.sql` |
| `trg_fac_updated_at` | `20260630000027_fixed_assets.sql` |
| `trg_flag_form2307_issued_for_ewt_reversal` | `20260714000005_form2307_received_claim_lifecycle.sql` |
| `trg_form2307_snapshot` | `20260703000005_report_snapshots_form2307.sql` |
| `trg_form2307_snapshot_guard` | `20260703000005_report_snapshots_form2307.sql` |
| `trg_form_2307_tracking_updated_at` | `20260629000007_cwt_2307.sql` |
| `trg_fund_transfers_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_generate_calendar_on_profile_change` | `20260628000005_sprint2_tax.sql` |
| `trg_gi_updated_at` | `20260630000028_inventory.sql` |
| `trg_guard_form2307_received_tracking` | `20260714000005_form2307_received_claim_lifecycle.sql` |
| `trg_guard_header_amortization_entries` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_amortization_schedules` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_asset_depreciation_entries` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_bank_adjustments` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_bank_reconciliations` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_book_tax_reconciliation` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_cash_count_sheets` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_cash_purchases` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_check_vouchers` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_credit_memos` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_debit_memos` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_delivery_receipts` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_ewt_returns` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_fixed_assets` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_fund_transfers` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_fwt_returns` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_goods_issues` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_income_tax_computations` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_inter_branch_transfers` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_itr_filings` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_journal_entries` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_mcit_computations` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_payment_vouchers` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_petty_cash_replenishments` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_petty_cash_vouchers` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_physical_count_sheets` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_pt_returns` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_purchase_orders` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_purchase_returns` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_receipts` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_receiving_reports` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_revenue_recognition_entries` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_revenue_recognition_schedules` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_sales_invoices` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_sales_orders` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_sales_quotations` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_stock_adjustments` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_stock_transfers` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_supplier_debit_memos` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_vendor_bills` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_vendor_credits` | `20260704000002_status_immutability.sql` |
| `trg_guard_header_withholding_remittances` | `20260713000005_withholding_remittance_flow.sql` |
| `trg_guard_lines_bank_recon_items` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_cash_purchase_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_check_voucher_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_credit_memo_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_debit_memo_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_delivery_receipt_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_goods_issue_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_journal_entry_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_physical_count_sheet_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_purchase_order_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_purchase_return_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_receiving_report_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_sales_order_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_sales_quotation_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_stock_adjustment_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_stock_transfer_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_supplier_debit_memo_lines` | `20260704000002_status_immutability.sql` |
| `trg_guard_lines_vendor_credit_lines` | `20260704000002_status_immutability.sql` |
| `trg_inter_branch_transfers_updated_at` | `20260630000023_banking_treasury_schema.sql` |
| `trg_je_dimensions_guard` | `20260704000001_je_line_dimensions.sql` |
| `trg_je_line_dimensions_guard` | `20260704000001_je_line_dimensions.sql` |
| `trg_journal_entries_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_journal_entry_balanced_deferred` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_journal_entry_line_posting_guard` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_journal_entry_lines_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_journal_entry_posting_guard` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_journal_entry_source_integrity` | `20260711000001_posting_engine_completion.sql` |
| `trg_journal_line_balanced_deferred` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_link_amortization_entry_je` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_link_fixed_asset_acquisition_je` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_link_fixed_asset_depreciation_je` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_link_fixed_asset_disposal_je` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_link_fixed_asset_impairment_je` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_link_purchase_return_je` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_link_revenue_recognition_entry_je` | `20260710000003_posting_engine_preview_trace.sql` |
| `trg_lock_unwrapped_posting_source` | `20260711000001_posting_engine_completion.sql` |
| `trg_new_company_grant_access` | `20260630000021_gap_fill.sql` |
| `trg_new_user_grant_companies` | `20260630000021_gap_fill.sql` |
| `trg_payment_voucher_lines_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_payment_voucher_post_ewt_profile` | `20260713000011_withholding_profile_gates.sql` |
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
| `trg_pvl_ewt_validation` | `20260713000011_withholding_profile_gates.sql` |
| `trg_receipt_line_cwt_validation` | `20260704000003_receipt_cwt_explicit_base.sql` |
| `trg_receipt_lines_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_receipts_updated_at` | `20260629000003_sprint5_ar.sql` |
| `trg_report_snapshot_vat_registration` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_require_cas_reversal_reason` | `20260710000005_cas_numbering_void_dat_controls.sql` |
| `trg_rjt_updated_at` | `20260630000025_accounting_module.sql` |
| `trg_rr_sched_updated_at` | `20260630000026_amortization_revenuerecon.sql` |
| `trg_rr_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_rrl_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_sadj_updated_at` | `20260630000028_inventory.sql` |
| `trg_sales_invoice_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` |
| `trg_sdm_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_sdml_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_si_line_vat_registration` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_si_updated_at` | `20260629000002_sprint5_sales.sql` |
| `trg_si_vat_registration_status` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_sil_updated_at` | `20260629000002_sprint5_sales.sql` |
| `trg_so_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_sol_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_sq_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_sql_updated_at` | `20260629000004_sprint5_so_dr.sql` |
| `trg_stx_updated_at` | `20260630000028_inventory.sql` |
| `trg_supplier_atc_default` | `20260701000014_supplier_atc_defaults.sql` |
| `trg_sync_number_series_shape` | `20260702000001_number_series_document_code_alignment.sql` |
| `trg_sync_receipt_totals_from_lines` | `20260714000004_cash_sale_receipt_total_semantics.sql` |
| `trg_tax_code_history_guard` | `20260713000012_tax_code_effective_date_governance.sql` |
| `trg_tax_code_version_rules` | `20260713000012_tax_code_effective_date_governance.sql` |
| `trg_transaction_event_approval_insert` | `20260713000014_transaction_events.sql` |
| `trg_transaction_event_approval_status` | `20260713000014_transaction_events.sql` |
| `trg_transaction_event_journal_insert` | `20260713000014_transaction_events.sql` |
| `trg_transaction_event_journal_source_link` | `20260713000014_transaction_events.sql` |
| `trg_transaction_event_journal_status` | `20260713000014_transaction_events.sql` |
| `trg_transaction_event_report_snapshot` | `20260713000014_transaction_events.sql` |
| `trg_vat_code_history_guard` | `20260713000012_tax_code_effective_date_governance.sql` |
| `trg_vat_return_snapshot` | `20260703000004_report_snapshots_vat_returns.sql` |
| `trg_vat_return_snapshot_guard` | `20260703000004_report_snapshots_vat_returns.sql` |
| `trg_vat_returns_registration` | `20260701000012_vat_registration_enforcement.sql` |
| `trg_vat_returns_status_reconciled` | `20260702000004_vat_ledger_gl_reconciliation.sql` |
| `trg_vat_returns_updated_at` | `20260701000002_vat.sql` |
| `trg_vat_wp_h_updated_at` | `20260701000002_vat.sql` |
| `trg_vb_line_vat_registration` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_vb_vat_registration_status` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_vc_line_vat_registration` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_vc_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_vc_vat_registration_status` | `20260710000002_vat_registration_all_documents.sql` |
| `trg_vcl_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_vendor_bill_accounting_ready_status` | `20260701000008_accounting_readiness_approval.sql` |
| `trg_vendor_bill_line_ewt_profile` | `20260713000011_withholding_profile_gates.sql` |
| `trg_vendor_bill_lines_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_vendor_bill_post_ewt_profile` | `20260713000011_withholding_profile_gates.sql` |
| `trg_vendor_bill_sync_ewt_expected` | `20260713000011_withholding_profile_gates.sql` |
| `trg_vendor_bills_updated_at` | `20260630000021_gap_fill.sql` |
| `trg_wh_updated_at` | `20260630000028_inventory.sql` |
| `trg_wht_export_profile` | `20260713000011_withholding_profile_gates.sql` |
| `trg_wis_updated_at` | `20260630000029_master_data_completion.sql` |
| `trg_withholding_remittances_updated_at` | `20260713000005_withholding_remittance_flow.sql` |
| `trg_zz_forbid_cas_void_evidence_row` | `20260712000004_cas_numbering_void_evidence.sql` |
| `trg_zz_forbid_cas_void_evidence_stmt` | `20260712000004_cas_numbering_void_evidence.sql` |
| `trg_zz_guard_cas_number_series` | `20260712000004_cas_numbering_void_evidence.sql` |
| `uom_updated_at` | `20260628000003_sprint2.sql` |
