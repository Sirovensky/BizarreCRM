#!/usr/bin/env bash
# Regenerate TODO-blocked.md from TODO.md by extracting every `- [!] …` item
# plus its indented continuation lines, preserving the nearest `## section` header.
#
# The autoloop reads TODO-blocked.md so it doesn't have to page through the
# 20,000-line TODO.md every wake. Run this after large TODO.md edits.

set -euo pipefail

cd "$(dirname "$0")/.."

awk '
BEGIN { collect = 0 }
/^- \[!\]/ { collect = 1; print; next }
/^- \[[ x]\]/ { collect = 0; next }
/^## / { collect = 0; print ""; print; print ""; next }
/^# / { collect = 0; next }
{ if (collect == 1) print }
' TODO.md > TODO-blocked.md.body

{
  printf '%s\n' '---'
  printf '%s\n' 'name: TODO blocked items'
  printf '%s\n' 'description: Auto-extracted [!] blocked items from TODO.md; loop reads this file, not TODO.md'
  printf '%s\n' 'type: project'
  printf '%s\n' '---'
  printf '\n'
  printf '> **AUTO-GENERATED.** Source of truth is `TODO.md`. Regenerate via `bash scripts/regen-blocked.sh`.\n'
  printf '> When an item flips to `[x]`, edit both this file and `TODO.md`; the next regen will reconcile.\n\n'
  cat TODO-blocked.md.body
} > TODO-blocked.md

rm TODO-blocked.md.body

count=$(grep -c '^- \[!\]' TODO-blocked.md || true)
lines=$(wc -l < TODO-blocked.md)
echo "TODO-blocked.md regenerated: ${count} blocked items, ${lines} lines."
