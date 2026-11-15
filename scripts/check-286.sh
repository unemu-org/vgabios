#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 the contributors to the unemu fork of the LGPL VGABIOS.
# Fail if the assembled ROM contains 386-only instructions.
# The unemu AT profiles run an 80286, so the ROM must be 8086/80186/80286 code.
# Usage: scripts/check-286.sh path/to/vgabios-<variant>.lst
set -euo pipefail
lst=${1:?usage: check-286.sh LISTING}
# Assembled lines of the as86 listing: line, address, bytes, source. Comments
# (lines whose source starts with "!" or ";") are not code.
pattern='\b(e[abcd]x|e[sd]i|e[bs]p|movzx|movsx|bt[src]?|set(n?[abcegloprsz]|[a-z]{2})|shld|shrd|lfs|lgs|lss|cdq|cwde|bsf|bsr)\b|\b[fg]s\b'
hits=$(grep -E -n "^[[:space:]]*[0-9]+[[:space:]]+[0-9A-F]{4}[[:space:]]+[0-9A-F]" "$lst" | grep -E -i "$pattern" || true)
# Opcode bytes: the 386 operand-size, address-size and FS/GS prefixes
# (66, 67, 64, 65) and 0F opcodes other than the 286 system group 0F00-0F06
# (near Jcc 0F8x, movzx, setcc, ...). Data directives (.byte, .word, ...)
# are skipped: font and table bytes are not instructions.
bytes=$(awk '
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/ && $3 ~ /^[0-9A-F]+$/ {
    src = $0
    sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9A-F]+([[:space:]]+[0-9A-F]+)*[[:space:]]*/, "", src)
    sub(/^[A-Za-z_.$][A-Za-z0-9_.$]*:[[:space:]]*/, "", src)
    if (src ~ /^\./) next
    op = $3
    if (op == "0F" && $4 ~ /^[0-9A-F][0-9A-F]/) op = op substr($4, 1, 2)
    if (op ~ /^(66|67|64|65)/ || (op ~ /^0F/ && substr(op, 3, 2) !~ /^0[0-6]$/))
      print FNR ": " $0
  }' "$lst")
if [ -n "$hits$bytes" ]; then
  echo "386-only instructions in $lst:" >&2
  [ -n "$hits" ] && echo "$hits" >&2
  [ -n "$bytes" ] && echo "$bytes" >&2
  exit 1
fi
echo "no 386-only instructions in $lst"
