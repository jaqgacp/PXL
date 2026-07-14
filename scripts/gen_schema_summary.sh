#!/usr/bin/env bash
# Generates docs/PXL/PXL_SCHEMA_SUMMARY.md from supabase/migrations/.
#
# Purpose: functions and views are redefined across the migration chain; the
# expensive question in every fix session is "where is the CURRENT definition
# of X". This emits an always-accurate object -> latest-migration map so agents
# read one table instead of grepping the whole chain.
#
# Usage: scripts/gen_schema_summary.sh   (rerun after adding migrations)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=docs/PXL/PXL_SCHEMA_SUMMARY.md
declare -A fn_last fn_count vw_last vw_count tb_created tb_alt_count tb_alt_last trg_last trg_table

for f in $(ls supabase/migrations/*.sql | sort); do
  base=$(basename "$f")
  while read -r name; do
    [ -z "$name" ] && continue
    fn_last[$name]=$base; fn_count[$name]=$(( ${fn_count[$name]:-0} + 1 ))
  done < <(grep -ohE 'CREATE (OR REPLACE )?FUNCTION +[a-zA-Z0-9_.]+' "$f" \
           | sed -E 's/.*FUNCTION +//; s/^public\.//' | sort -u)
  while read -r name; do
    [ -z "$name" ] && continue
    vw_last[$name]=$base; vw_count[$name]=$(( ${vw_count[$name]:-0} + 1 ))
  done < <(grep -ohE 'CREATE (OR REPLACE )?VIEW +[a-zA-Z0-9_.]+' "$f" \
           | sed -E 's/.*VIEW +//; s/^public\.//' | sort -u)
  while read -r name; do
    [ -z "$name" ] && continue
    [ -z "${tb_created[$name]:-}" ] && tb_created[$name]=$base
  done < <(grep -ohE 'CREATE TABLE (IF NOT EXISTS )?[a-zA-Z0-9_.]+' "$f" \
           | sed -E 's/.*TABLE (IF NOT EXISTS )?//; s/^public\.//' | sort -u)
  while read -r name; do
    [ -z "$name" ] && continue
    tb_alt_count[$name]=$(( ${tb_alt_count[$name]:-0} + 1 )); tb_alt_last[$name]=$base
  done < <(grep -ohE 'ALTER TABLE (IF EXISTS )?(ONLY )?[a-zA-Z0-9_.]+' "$f" \
           | sed -E 's/.*TABLE (IF EXISTS )?(ONLY )?//; s/^public\.//' | sort -u)
  while IFS=$'\t' read -r name table_name; do
    [ -z "$name" ] && continue
    table_name=${table_name#public.}
    trg_last[$name]=$base
    trg_table[$name]=$table_name
  done < <(perl -0777 -ne '
      while (/CREATE\s+(?:OR\s+REPLACE\s+)?(?:CONSTRAINT\s+)?TRIGGER\s+([a-zA-Z0-9_]+)\b.*?\bON\s+(?:ONLY\s+)?([a-zA-Z0-9_.]+)/sig) {
        print "$1\t$2\n";
      }
    ' "$f" | sort -u)

  while read -r name; do
    [ -z "$name" ] && continue
    name=${name#public.}
    [ "${name#pg_temp.}" != "$name" ] && continue
    unset 'tb_created[$name]' 'tb_alt_count[$name]' 'tb_alt_last[$name]'
    for trg in "${!trg_table[@]}"; do
      if [ "${trg_table[$trg]}" = "$name" ]; then
        unset 'trg_last[$trg]' 'trg_table[$trg]'
      fi
    done
  done < <(perl -ne '
      while (/DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?((?:(?:public|pg_temp)\.)?[a-zA-Z0-9_]+)/ig) {
        print "$1\n";
      }
    ' "$f" | sort -u)
done

{
  echo "# PXL Schema Summary"
  echo
  echo "GENERATED FILE — do not hand-edit. Regenerate with \`scripts/gen_schema_summary.sh\` after adding migrations (CI does not enforce freshness; regenerate in any session that adds a migration)."
  echo
  echo "Maps every database object to the migration holding its CURRENT definition, so agents do not grep the full chain. Column \"Defs\" counts how many migrations (re)define the object — a high count means the object has history worth checking before editing."
  echo
  echo "Generated: $(date +%F). Migrations scanned: $(ls supabase/migrations/*.sql | wc -l). Tests present: $(ls supabase/tests/*.sql | wc -l)."
  echo
  echo "## Functions (${#fn_last[@]})"
  echo
  echo "| Function | Latest definition | Defs |"
  echo "| -------- | ----------------- | ---- |"
  for k in $(printf '%s\n' "${!fn_last[@]}" | sort); do
    echo "| \`$k\` | \`${fn_last[$k]}\` | ${fn_count[$k]} |"
  done
  echo
  echo "## Views (${#vw_last[@]})"
  echo
  echo "| View | Latest definition | Defs |"
  echo "| ---- | ----------------- | ---- |"
  for k in $(printf '%s\n' "${!vw_last[@]}" | sort); do
    echo "| \`$k\` | \`${vw_last[$k]}\` | ${vw_count[$k]} |"
  done
  echo
  echo "## Tables (${#tb_created[@]})"
  echo
  echo "| Table | Created in | Alters | Last altered in |"
  echo "| ----- | ---------- | ------ | --------------- |"
  for k in $(printf '%s\n' "${!tb_created[@]}" | sort); do
    echo "| \`$k\` | \`${tb_created[$k]}\` | ${tb_alt_count[$k]:-0} | \`${tb_alt_last[$k]:-—}\` |"
  done
  echo
  echo "## Triggers (${#trg_last[@]})"
  echo
  echo "| Trigger | Latest definition |"
  echo "| ------- | ----------------- |"
  for k in $(printf '%s\n' "${!trg_last[@]}" | sort); do
    echo "| \`$k\` | \`${trg_last[$k]}\` |"
  done
} > "$OUT"

echo "Wrote $OUT: ${#fn_last[@]} functions, ${#vw_last[@]} views, ${#tb_created[@]} tables, ${#trg_last[@]} triggers"
