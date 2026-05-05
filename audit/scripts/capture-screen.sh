#!/usr/bin/env bash
# capture-screen.sh — capture a device screenshot over adb, resize to max
# 1200px on the long edge, write PNG into docs/m3-expressive-audit/.
#
# Usage: ./scripts/capture-screen.sh <name>
#   <name> — filename without extension (e.g. "pos-entry-top")
#
# Requires: Python + Pillow, adb in platform-tools, a connected device
# (USB or `adb connect <ip>:<port>` already done).
set -euo pipefail

NAME="${1:?usage: capture-screen.sh <name>}"
ADB="${ADB:-/c/Users/Owner/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
# If $ADB_DEVICE is set, target that serial; otherwise pick the first
# non-tls-connect device line (prefers the IP:port wireless entry over
# the mDNS duplicate that newer Android + adb pair sometimes expose).
if [[ -n "${ADB_DEVICE:-}" ]]; then
    SERIAL="$ADB_DEVICE"
else
    SERIAL="$("$ADB" devices | awk '/device$/ && !/_adb-tls-connect/ {print $1; exit}')"
fi
if [[ -z "$SERIAL" ]]; then
    echo "no adb device; run: $ADB devices" >&2
    exit 1
fi
# Resolve the script's own directory, then walk up to the repo root —
# more reliable than `git rev-parse --show-toplevel` which returns the
# current worktree when invoked from one, splitting captures across
# `.claude/worktrees/…/docs/…` and the canonical `docs/…`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$REPO_ROOT/docs/m3-expressive-audit"
TMP_RAW="$(mktemp --suffix=.png)"
trap 'rm -f "$TMP_RAW"' EXIT

mkdir -p "$OUT_DIR"
"$ADB" -s "$SERIAL" exec-out screencap -p > "$TMP_RAW"

python - "$TMP_RAW" "$OUT_DIR/$NAME.png" <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src)
img.thumbnail((1200, 1200), Image.LANCZOS)
img.save(dst, 'PNG', optimize=True)
print(f"{dst} — {img.width}x{img.height}")
PY
