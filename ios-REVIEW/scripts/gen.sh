#!/usr/bin/env bash
# Regenerate the Xcode project from project.yml. Use this instead of bare
# `xcodegen generate` — it first writes a fresh Info.plist (which xcodegen
# does not reliably do from the YAML) and then runs xcodegen.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "→ writing Info.plist"
bash "${SCRIPT_DIR}/write-info-plist.sh"

echo "→ running xcodegen"
cd "${IOS_DIR}"
xcodegen generate

echo
echo "✓ project ready — open BizarreCRM.xcodeproj"
