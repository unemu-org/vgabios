#!/usr/bin/env bash
# Fail if the assembled ROM contains 386-only instructions.
# The unemu AT profiles run an 80286, so the ROM must be 8086/80186/80286 code.
# Usage: scripts/check-286.sh path/to/vgabios-<variant>.lst
set -euo pipefail
lst=${1:?usage: check-286.sh LISTING}
# Assembled lines of the as86 listing: line, address, bytes, source. Comments
# (lines whose source starts with "!" or ";") are not code.
pattern='\b(e[abcd]x|e[sd]i|e[bs]p|movzx|movsx|bt[src]?|set(n?[abcegloprsz]|[a-z]{2})|shld|shrd|lfs|lgs|lss|cdq|cwde|bsf|bsr)\b|\b[fg]s\b'
hits=$(grep -E -n "^[[:space:]]*[0-9]+[[:space:]]+[0-9A-F]{4}[[:space:]]+[0-9A-F]" "$lst" | grep -E -i "$pattern" || true)
if [ -n "$hits" ]; then
  echo "386-only instructions in $lst:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "no 386-only instructions in $lst"
