#!/usr/bin/env bash
# Download the OFL-licensed brand fonts into ios/App/Resources/Fonts/.
# Idempotent — skips files already present.
#
# Font families (per §30.4 / §80.8):
#   Bebas Neue   — display/title (large numbers, screen headers, CTAs)
#   League Spartan — accent/secondary headings
#   Roboto       — body/UI workhorse
#   Roboto Mono  — monospace (IDs, SKUs, IMEIs, barcodes)
#   Roboto Slab  — optional slab accent (invoice print header)
#
# Run once after cloning the repo, and again whenever fonts need updating.
# Next step: cd ios && bash scripts/gen.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/App/Resources/Fonts"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${FONTS_DIR}"

# Files we need (matches UIAppFonts in write-info-plist.sh).
REQUIRED=(
    "BebasNeue-Regular.ttf"
    "LeagueSpartan-Medium.ttf"
    "LeagueSpartan-SemiBold.ttf"
    "LeagueSpartan-Bold.ttf"
    "Roboto-Regular.ttf"
    "Roboto-Medium.ttf"
    "Roboto-SemiBold.ttf"
    "Roboto-Bold.ttf"
    "RobotoMono-Regular.ttf"
    "RobotoSlab-SemiBold.ttf"
)

missing=()
for f in "${REQUIRED[@]}"; do
    if [ ! -f "${FONTS_DIR}/${f}" ]; then
        missing+=("${f}")
    fi
done

if [ ${#missing[@]} -eq 0 ]; then
    echo "All brand fonts already in place at ${FONTS_DIR}"
    exit 0
fi

echo "Fetching brand fonts into ${FONTS_DIR}..."

GF_BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"

# --- Bebas Neue ---------------------------------------------------------------
echo "  Bebas Neue"
curl -fsSL -o "${FONTS_DIR}/BebasNeue-Regular.ttf" \
    "${GF_BASE}/bebasneue/BebasNeue-Regular.ttf" || {
    echo "  WARNING: could not fetch BebasNeue-Regular.ttf — add manually to ${FONTS_DIR}"
}

# --- League Spartan -----------------------------------------------------------
echo "  League Spartan"
for weight in "Medium" "SemiBold" "Bold"; do
    dest="${FONTS_DIR}/LeagueSpartan-${weight}.ttf"
    # Google Fonts hosts it as a variable font; try static first, then variable.
    if ! curl -fsSL -o "${dest}" \
        "${GF_BASE}/leaguespartan/static/LeagueSpartan-${weight}.ttf" 2>/dev/null; then
        echo "  WARNING: could not fetch LeagueSpartan-${weight}.ttf — add manually to ${FONTS_DIR}"
    fi
done

# --- Roboto ------------------------------------------------------------------
echo "  Roboto"
# Google Fonts ships static Roboto via the main branch.
ROBOTO_BASE="${GF_BASE}/roboto/static"
for weight in "Regular" "Medium" "Bold"; do
    dest="${FONTS_DIR}/Roboto-${weight}.ttf"
    if ! curl -fsSL -o "${dest}" \
        "${ROBOTO_BASE}/Roboto-${weight}.ttf" 2>/dev/null; then
        echo "  WARNING: could not fetch Roboto-${weight}.ttf — add manually to ${FONTS_DIR}"
    fi
done

# Roboto SemiBold is not a separate static weight in the old Google Fonts repo;
# use the variable font subset or fall back gracefully to Medium at runtime.
# We ship a copy from the Roboto v3 ZIP which does include SemiBold.
ROBOTO_ZIP_URL="https://github.com/googlefonts/roboto/releases/download/v2.138/roboto-android.zip"
echo "  Roboto SemiBold (from release archive)"
if curl -fsSL -o "${TMP_DIR}/roboto.zip" "${ROBOTO_ZIP_URL}" 2>/dev/null; then
    unzip -q -o "${TMP_DIR}/roboto.zip" -d "${TMP_DIR}/roboto" 2>/dev/null || true
    src="$(find "${TMP_DIR}/roboto" -type f -iname "Roboto-SemiBold.ttf" | head -n 1 || true)"
    if [ -n "${src}" ]; then
        cp "${src}" "${FONTS_DIR}/Roboto-SemiBold.ttf"
    else
        echo "  WARNING: Roboto-SemiBold.ttf not found in release archive — add manually to ${FONTS_DIR}"
        # Fallback: copy Medium as SemiBold placeholder so fonts don't crash.
        if [ -f "${FONTS_DIR}/Roboto-Medium.ttf" ]; then
            cp "${FONTS_DIR}/Roboto-Medium.ttf" "${FONTS_DIR}/Roboto-SemiBold.ttf"
            echo "  Using Roboto-Medium.ttf as placeholder for Roboto-SemiBold.ttf"
        fi
    fi
else
    echo "  WARNING: Could not download Roboto release archive — add Roboto-SemiBold.ttf manually"
fi

# --- Roboto Mono --------------------------------------------------------------
echo "  Roboto Mono"
for weight in "Regular"; do
    dest="${FONTS_DIR}/RobotoMono-${weight}.ttf"
    if ! curl -fsSL -o "${dest}" \
        "${GF_BASE}/robotomono/static/RobotoMono-${weight}.ttf" 2>/dev/null; then
        echo "  WARNING: could not fetch RobotoMono-${weight}.ttf — add manually to ${FONTS_DIR}"
    fi
done

# --- Roboto Slab -------------------------------------------------------------
echo "  Roboto Slab"
dest="${FONTS_DIR}/RobotoSlab-SemiBold.ttf"
if ! curl -fsSL -o "${dest}" \
    "${GF_BASE}/robotoslab/static/RobotoSlab-SemiBold.ttf" 2>/dev/null; then
    echo "  WARNING: could not fetch RobotoSlab-SemiBold.ttf — add manually to ${FONTS_DIR}"
fi

# --- Verify ------------------------------------------------------------------
echo ""
echo "Result:"
missing_after=()
for f in "${REQUIRED[@]}"; do
    if [ -f "${FONTS_DIR}/${f}" ]; then
        size_bytes=$(stat -f%z "${FONTS_DIR}/${f}" 2>/dev/null || stat -c%s "${FONTS_DIR}/${f}")
        echo "  OK  ${f}  (${size_bytes} bytes)"
    else
        echo "  MISS  ${f}"
        missing_after+=("${f}")
    fi
done

if [ ${#missing_after[@]} -ne 0 ]; then
    echo ""
    echo "Some fonts are still missing — download them manually and drop into:"
    echo "  ${FONTS_DIR}"
    echo "The app will fall back to SF Pro at runtime; no crash."
    exit 1
fi

echo ""
echo "Next: cd ios && bash scripts/gen.sh && open BizarreCRM.xcodeproj"
