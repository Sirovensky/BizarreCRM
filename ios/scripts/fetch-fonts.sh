#!/usr/bin/env bash
# Download the OFL-licensed brand fonts (Inter, Barlow Condensed, JetBrains Mono)
# into ios/App/Resources/Fonts/. Idempotent — skips files already present.
#
# Run once after cloning the repo, and again whenever fonts need updating.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/App/Resources/Fonts"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${FONTS_DIR}"

# Files we need (matches UIAppFonts in Info.plist).
REQUIRED=(
    "Inter-Regular.ttf"
    "Inter-Medium.ttf"
    "Inter-SemiBold.ttf"
    "Inter-Bold.ttf"
    "BarlowCondensed-SemiBold.ttf"
    "BarlowCondensed-Bold.ttf"
    "JetBrainsMono-Regular.ttf"
    "JetBrainsMono-Medium.ttf"
)

missing=()
for f in "${REQUIRED[@]}"; do
    if [ ! -f "${FONTS_DIR}/${f}" ]; then
        missing+=("${f}")
    fi
done

if [ ${#missing[@]} -eq 0 ]; then
    echo "✓ All brand fonts already in place at ${FONTS_DIR}"
    exit 0
fi

echo "Fetching brand fonts into ${FONTS_DIR}…"

# --- Inter -------------------------------------------------------------------
INTER_ZIP_URL="https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"
echo "• Inter 4.1"
curl -fsSL -o "${TMP_DIR}/inter.zip" "${INTER_ZIP_URL}"
unzip -q -o "${TMP_DIR}/inter.zip" -d "${TMP_DIR}/inter"
# Look for the static Inter Desktop fonts by canonical name.
for weight in Regular Medium SemiBold Bold; do
    src="$(find "${TMP_DIR}/inter" -type f -iname "Inter-${weight}.ttf" | head -n 1 || true)"
    if [ -n "${src}" ]; then
        cp "${src}" "${FONTS_DIR}/Inter-${weight}.ttf"
    else
        # Newer Inter builds use the "Static/Inter_18pt-*" path; fall back to that.
        alt="$(find "${TMP_DIR}/inter" -type f -iname "Inter_18pt-${weight}.ttf" | head -n 1 || true)"
        if [ -n "${alt}" ]; then
            cp "${alt}" "${FONTS_DIR}/Inter-${weight}.ttf"
        else
            echo "  ⚠ Could not locate Inter-${weight}.ttf in the release archive"
        fi
    fi
done

# --- Barlow Condensed --------------------------------------------------------
echo "• Barlow Condensed"
BARLOW_BASE="https://raw.githubusercontent.com/google/fonts/main/ofl/barlowcondensed"
for weight_pair in "SemiBold:BarlowCondensed-SemiBold.ttf" "Bold:BarlowCondensed-Bold.ttf"; do
    weight="${weight_pair%%:*}"
    file="${weight_pair##*:}"
    curl -fsSL -o "${FONTS_DIR}/${file}" "${BARLOW_BASE}/${file}" || {
        echo "  ⚠ Google Fonts mirror miss for ${file} — trying Google Fonts GitHub fallback"
        curl -fsSL -o "${FONTS_DIR}/${file}" "https://github.com/google/fonts/raw/main/ofl/barlowcondensed/${file}"
    }
done

# --- JetBrains Mono ----------------------------------------------------------
JB_ZIP_URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
echo "• JetBrains Mono 2.304"
curl -fsSL -o "${TMP_DIR}/jetbrains.zip" "${JB_ZIP_URL}"
unzip -q -o "${TMP_DIR}/jetbrains.zip" -d "${TMP_DIR}/jetbrains"
for weight in Regular Medium; do
    src="$(find "${TMP_DIR}/jetbrains" -type f -iname "JetBrainsMono-${weight}.ttf" | head -n 1 || true)"
    if [ -n "${src}" ]; then
        cp "${src}" "${FONTS_DIR}/JetBrainsMono-${weight}.ttf"
    else
        echo "  ⚠ Could not locate JetBrainsMono-${weight}.ttf in the release archive"
    fi
done

# --- Verify ------------------------------------------------------------------
echo
echo "Result:"
missing_after=()
for f in "${REQUIRED[@]}"; do
    if [ -f "${FONTS_DIR}/${f}" ]; then
        size_bytes=$(stat -f%z "${FONTS_DIR}/${f}" 2>/dev/null || stat -c%s "${FONTS_DIR}/${f}")
        echo "  ✓ ${f}  (${size_bytes} bytes)"
    else
        echo "  ✗ ${f}  MISSING"
        missing_after+=("${f}")
    fi
done

if [ ${#missing_after[@]} -ne 0 ]; then
    echo
    echo "Some fonts are still missing — download them manually and drop into:"
    echo "  ${FONTS_DIR}"
    exit 1
fi

echo
echo "Next: cd ios && xcodegen generate && open BizarreCRM.xcodeproj"
