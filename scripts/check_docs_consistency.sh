#!/usr/bin/env bash
# Docs-consistency gate (PXL-DA-020).
#
# Checks, cheaply and deterministically:
#   1. Every finding in the Findings Status Index matches the status recorded
#      in its main-table row and/or New Finding Detail section (the index is
#      authoritative; any disagreement is an error).
#   2. Every finding that exists in the document appears in the index.
#   3. The transaction matrix carries the current Findings Status Index checksum
#      and references every non-passed finding still requiring follow-up.
#   4. Every `supabase/tests/*.sql` file referenced by the accounting test book
#      exists on disk, and every test file on disk is referenced by the book.
#
# Usage: scripts/check_docs_consistency.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DOC="docs/PXL/PXL_END_TO_END_AUDIT_FINDINGS.md"
BOOK="docs/PXL/02. Accounting Core/PXL_ACCOUNTING_TEST_BOOK.md"
MATRIX="docs/PXL/04. Transaction Framework/PXL_TRANSACTION_MATRIX.md"
fail=0

# ── Parse the authoritative index (4-cell rows: ID | Severity | Status | Next) ─
index=$(awk '/^## Findings Status Index/{f=1;next} f&&/^## /{exit} f' "$DOC" \
  | awk -F'|' 'NF==6 && $2 ~ /PXL-(AUD|DA)-[0-9]+/ {
      gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$4); print $2"\t"$4 }')

if [ -z "$index" ]; then
  echo "FAIL: Findings Status Index not found or empty in $DOC"
  exit 1
fi

# ── Parse main-table rows (wide rows, status is the 4th cell) ──────────────────
main=$(awk -F'|' 'NF>=13 && $2 ~ /PXL-(AUD|DA)-[0-9]+/ {
    gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$5); print $2"\t"$5 }' "$DOC")

# ── Parse New Finding Detail sections ───────────────────────────────────────────
detail=$(awk '
  /^### New Finding Detail - PXL-/ { id=$NF }
  id && /^\| Status \|/ {
    s=$0; sub(/^\| Status \| */,"",s); sub(/ *\|.*$/,"",s);
    print id"\t"s; id="" }' "$DOC")

# ── 1+2. Status agreement, index completeness ───────────────────────────────────
declare -A idx
while IFS=$'\t' read -r id st; do idx["$id"]="$st"; done <<< "$index"

check_against() {
  local src_name=$1 rows=$2
  while IFS=$'\t' read -r id st; do
    [ -z "$id" ] && continue
    if [ -z "${idx[$id]:-}" ]; then
      echo "FAIL: $id appears in $src_name but is missing from the Findings Status Index"
      fail=1
    elif [ "${idx[$id]}" != "$st" ]; then
      echo "FAIL: $id status mismatch — index says '${idx[$id]}', $src_name says '$st'"
      fail=1
    fi
  done <<< "$rows"
}
check_against "main table" "$main"
check_against "detail section" "$detail"

# Every indexed finding must exist somewhere in the document body
for id in "${!idx[@]}"; do
  if ! grep -q -- "$id" <(printf '%s\n%s\n' "$main" "$detail"); then
    echo "FAIL: $id is in the index but has no main-table row or detail section"
    fail=1
  fi
done

# ── 3. Transaction matrix sync ─────────────────────────────────────────────────
count_status() {
  local status=$1
  awk -F'\t' -v wanted="$status" '$2 == wanted { count++ } END { print count + 0 }' <<< "$index"
}

total_count=$(wc -l <<< "$index" | tr -d ' ')
passed_count=$(count_status "Retested Passed")
in_progress_count=$(count_status "In Progress")
open_count=$(count_status "Open")
matrix_checksum="Findings Status Index checksum: ${passed_count} Retested Passed / ${in_progress_count} In Progress / ${open_count} Open (${total_count} findings)"

if ! grep -Fq "$matrix_checksum" "$MATRIX"; then
  echo "FAIL: $MATRIX is missing the current checksum: $matrix_checksum"
  fail=1
fi

active_ids=$(awk -F'\t' '$2 != "Retested Passed" { print $1 }' <<< "$index")
while read -r id; do
  [ -z "$id" ] && continue
  if ! grep -q -- "$id" "$MATRIX"; then
    echo "FAIL: active finding $id is missing from $MATRIX"
    fail=1
  fi
done <<< "$active_ids"

# ── 4. Test book <-> test files ────────────────────────────────────────────────
book_refs=$(grep -oE 'supabase/tests/[0-9a-z_]+\.sql' "$BOOK" | sort -u)
while read -r f; do
  [ -f "$f" ] || { echo "FAIL: $BOOK references missing file $f"; fail=1; }
done <<< "$book_refs"

for f in supabase/tests/*.sql; do
  grep -q "$f" "$BOOK" || { echo "FAIL: $f exists but is not referenced in $BOOK"; fail=1; }
done

if [ "$fail" -eq 0 ]; then
  echo "OK: findings index consistent (${total_count} findings); matrix checksum/current findings in sync; test book matches $(ls supabase/tests/*.sql | wc -l) test files"
fi
exit $fail
