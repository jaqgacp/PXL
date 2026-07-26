-- POSTING-ENGINE-P51-010 — Ready-to-arm closure compatibility under P5.2
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);

CREATE TEMP VIEW v_forward_writer AS
SELECT unnest(ARRAY[
  'fn_post_credit_memo_vat_lump_impl',
  'fn_post_debit_memo_vat_lump_impl',
  'fn_post_vendor_credit_vat_lump_impl',
  'fn_post_manual_je',
  'fn_post_goods_issue_source_locked_impl',
  'fn_post_physical_count_source_locked_impl',
  'fn_post_stock_adjustment_source_locked_impl',
  'fn_post_stock_transfer_source_locked_impl',
  'fn_post_bank_adjustment_source_locked_impl',
  'fn_post_fund_transfer_source_locked_impl',
  'fn_post_inter_branch_transfer_source_locked_impl',
  'fn_approve_petty_cash_voucher_source_locked_impl',
  'fn_post_petty_cash_replenishment_source_locked_impl',
  'fn_post_check_voucher',
  'fn_post_depreciation_entry_source_locked_impl',
  'fn_post_amortization_entry_source_locked_impl',
  'fn_post_revenue_recognition_entry_source_locked_impl',
  'fn_register_fixed_asset',
  'fn_dispose_fixed_asset',
  'fn_record_impairment',
  'fn_execute_recurring_template_source_locked_impl',
  'fn_close_fiscal_year',
  'fn_complete_purchase_return_source_locked_impl',
  'fn_save_cash_sale'
]) AS proname;

CREATE TEMP VIEW v_update_writer AS
SELECT unnest(ARRAY[
  'fn_post_sales_invoice',
  'fn_post_vendor_bill',
  'fn_post_receipt',
  'fn_post_cash_purchase_source_locked_impl'
]) AS proname;

CREATE TEMP VIEW v_sanctioned_mutator AS
SELECT unnest(ARRAY[
  'fn_create_posted_journal_entry',
  'fn_reverse_posted_journal_entry',
  'fn_finalize_journal_entry',
  'fn_add_posting_line',
  'fn_add_posting_line_push',
  'fn_add_sales_invoice_posting_line'
]) AS proname;

SELECT is((SELECT count(*)::int FROM v_forward_writer), 24,
  'the authoritative forward-writer census remains 24');                              -- 1

SELECT is(
  (SELECT count(*)::int
     FROM v_forward_writer w
     LEFT JOIN pg_proc p ON p.proname=w.proname
     LEFT JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE n.oid IS NULL),
  0, 'all 24 authoritative forward writers remain present');                          -- 2

SELECT is(
  (SELECT count(*)::int
     FROM v_forward_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~
      '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'zero forward writers mutate either accounting ledger table directly');          -- 3

SELECT is(
  (SELECT count(*)::int
     FROM v_update_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~
      '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'),
  0, 'the four legacy header UPDATE paths are also fully drained');                    -- 4

SELECT set_eq(
  $$SELECT p.proname::text
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public'
       AND p.prosrc ~
         '(INSERT INTO|UPDATE|DELETE FROM)\s+journal_(entries|entry_lines)'$$,
  $$VALUES ('fn_create_posted_journal_entry'),
           ('fn_reverse_posted_journal_entry'),
           ('fn_finalize_journal_entry'),
           ('fn_add_posting_line'),
           ('fn_add_posting_line_push'),
           ('fn_add_sales_invoice_posting_line')$$,
  'only the six frozen sanctioned persistence functions contain ledger mutation');   -- 5

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='fn_add_posting_line_core_20260718'),
  0, 'the unreachable legacy raw-mutation helper is removed');                        -- 6

SELECT ok(
  fn_posting_kernel_origin(
    'PL/pgSQL function fn_create_posted_journal_entry(uuid,uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_reverse_posted_journal_entry(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_finalize_journal_entry(uuid) line 1'),
  'all three sanctioned header kernels classify as kernel-origin');                   -- 7

SELECT ok(
  fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line_push(uuid) line 1')
  AND fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_sales_invoice_posting_line(uuid) line 1'),
  'all three sanctioned line helpers classify as kernel-origin');                     -- 8

SELECT ok(
  NOT fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line_core_20260718(uuid) line 1')
  AND NOT fn_posting_kernel_origin(
    'PL/pgSQL function fn_add_posting_line_extra(uuid) line 1')
  AND NOT fn_posting_kernel_origin(
    'PL/pgSQL function fn_finalize_journal_entry_bypass(uuid) line 1')
  AND NOT fn_posting_kernel_origin(
    'PL/pgSQL function x_fn_create_posted_journal_entry_extra(uuid) line 1'),
  'classifier lookalikes cannot inherit kernel-origin');                              -- 9

SELECT is(
  (SELECT count(*)::int
     FROM v_sanctioned_mutator s
     JOIN pg_proc p ON p.proname=s.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'),
  6, 'the classifier has one extant function for every sanctioned member');           -- 10

SELECT is(
  (SELECT count(*)::int
     FROM v_sanctioned_mutator s
     JOIN pg_proc p ON p.proname=s.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE has_function_privilege('authenticated', p.oid, 'EXECUTE')
       OR has_function_privilege('anon', p.oid, 'EXECUTE')),
  0, 'no sanctioned persistence function is client-callable');                       -- 11

SELECT ok(
  (SELECT p.prosrc ~ 'c_enforce\s+CONSTANT\s+BOOLEAN\s*:=\s*true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the later P5.2 phase has armed the ready guard');                                   -- 12

SELECT is(
  (SELECT count(*)::int
     FROM pg_trigger t
    WHERE NOT t.tgisinternal
      AND t.tgfoid='public.fn_guard_journal_kernel_origin()'::regprocedure
      AND t.tgrelid IN (
        'public.journal_entries'::regclass,
        'public.journal_entry_lines'::regclass)),
  2, 'the armed guard remains wired to both accounting ledger tables');               -- 13

SELECT ok(
  (SELECT p.prosrc ~ 'fn_demo_reset_bypass_authorized'
      AND p.prosrc !~ 'current_setting'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_guard_journal_kernel_origin'),
  'the frozen maintenance classification remains unchanged and non-forgeable');       -- 14

SELECT is(
  (SELECT count(*)::int FROM sys_posting_guard_violations),
  0, 'the clean readiness census contains zero violation events');                    -- 15

SELECT is(
  (SELECT count(*)::int
     FROM v_forward_writer w
     JOIN pg_proc p ON p.proname=w.proname
     JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.prosrc ~ 'posting_origin\s*:=|posting_origin\s*='),
  0, 'no forward writer fabricates posting_origin through an assignment');            -- 16

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_create_posted_journal_entry'),
  1, 'the extended header kernel retains exactly one unambiguous signature');          -- 17

SELECT is(
  (SELECT count(*)::int
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  1, 'the extended finalizer retains exactly one unambiguous signature');              -- 18

SELECT ok(
  (SELECT pg_get_function_arguments(p.oid) ~
          'p_emit_origin_update boolean DEFAULT false'
      AND pg_get_function_arguments(p.oid) ~
          'p_assert_source boolean DEFAULT true'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_create_posted_journal_entry'),
  'header-kernel compatibility modes remain explicit and default-safe');              -- 19

SELECT ok(
  (SELECT pg_get_function_arguments(p.oid) ~
          'p_persist_totals boolean DEFAULT false'
      AND pg_get_function_arguments(p.oid) ~
          'p_link_source boolean DEFAULT false'
      AND pg_get_function_arguments(p.oid) ~
          'p_mark_auto_reversal boolean DEFAULT false'
      AND pg_get_function_arguments(p.oid) ~
          'p_discard_journal boolean DEFAULT false'
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='fn_finalize_journal_entry'),
  'all finalizer compatibility modes remain explicit and default-off');               -- 20

SELECT * FROM finish();
ROLLBACK;
