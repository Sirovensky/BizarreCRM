#!/usr/bin/env bash
# BizarreCRM macOS Gateway (Finder-double-clickable)
# ===================================================
# Thin gateway: verifies Node.js >= v22 is on PATH, tries to install via
# Homebrew if missing, falls back to opening nodejs.org. Then exec's the
# universal setup.mjs script.
#
# .command extension is the macOS convention for double-clickable shell
# scripts in Finder. The `setup.sh` sibling file is identical and exists
# for operators using `./setup.sh` from a terminal.
#
# This file is INTENTIONALLY MINIMAL. Bulk install logic lives in
# setup.mjs — see OPS-DEFERRED-001 in TODO.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_NODE_MAJOR=22
REJECTED_NODE_MAJOR=25
NODE_DOWNLOAD_URL="https://nodejs.org/en/download/"

# Defined first so it can be called from anywhere below.
open_download_page() {
  echo
  echo "Could not install Node.js automatically."
  echo "Opening the official Node.js download page in your browser."
  echo "Install the LTS (v22 or newer), then re-run this script."
  echo
  open "${NODE_DOWNLOAD_URL}" || true
  read -rp "Press Enter to exit..."
  exit 1
}

echo "============================================"
echo "   BizarreCRM Setup (macOS Gateway)"
echo "============================================"
echo

# ── Step 1: Check Node.js ────────────────────────────────────────
echo "[1/3] Checking Node.js..."
NODE_OK=0
if command -v node >/dev/null 2>&1; then
  # `node --version` prints e.g. "v22.11.0"; strip leading v + take major.
  NODE_VERSION="$(node --version 2>/dev/null || true)"
  NODE_MAJOR="${NODE_VERSION#v}"
  NODE_MAJOR="${NODE_MAJOR%%.*}"
  if [[ -n "${NODE_MAJOR}" && "${NODE_MAJOR}" =~ ^[0-9]+$ && "${NODE_MAJOR}" -ge "${REQUIRED_NODE_MAJOR}" && "${NODE_MAJOR}" -lt "${REJECTED_NODE_MAJOR}" ]]; then
    echo "OK - Node.js ${NODE_VERSION} detected."
    NODE_OK=1
  elif [[ -n "${NODE_MAJOR}" && "${NODE_MAJOR}" -ge "${REJECTED_NODE_MAJOR}" ]]; then
    # Node too new: fall through to the install branch below. brew install
    # node@22 + brew link --overwrite --force will downgrade the active
    # node binary on PATH (works whether the existing Node was brew- or
    # MSI-installed, because keg-only versioned formulae are independent).
    echo "Node.js ${NODE_VERSION} detected, but repo engines require Node 22-24."
    echo "Attempting to install Node 22 LTS alongside and relink it via Homebrew..."
    NODE_OK=0
  else
    echo "Node.js ${NODE_VERSION:-(unknown)} detected, but v${REQUIRED_NODE_MAJOR}+ required."
  fi
else
  echo "Node.js not found."
fi

# ── Step 2: Try to install Node.js via Homebrew ──────────────────
if [[ "${NODE_OK}" -eq 0 ]]; then
  echo
  echo "[2/3] Attempting to install Node.js via Homebrew..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not available on this machine."
    open_download_page
  fi

  # `brew install node@22` pins to the LTS major. brew handles its own sudo
  # prompts and PATH updates. If install fails, fall through to the
  # download page rather than guessing what went wrong.
  if ! brew install node@22; then
    echo "brew install failed."
    open_download_page
  fi

  # Unlink any other `node` formula currently linked (e.g. v25), then
  # link node@22 over the top. `--overwrite --force` tolerates pre-existing
  # symlinks. Failures here are best-effort: the next `command -v node`
  # check is the source of truth.
  brew unlink node 2>/dev/null || true
  brew link --overwrite --force node@22 || true

  if ! command -v node >/dev/null 2>&1; then
    echo
    echo "Node.js installed via Homebrew, but this shell's PATH was not refreshed."
    echo "Close this terminal window and re-run setup from a NEW terminal."
    read -rp "Press Enter to exit..."
    exit 1
  fi
  echo "OK - Node.js installed via Homebrew."
fi

# ── Step 3: Hand off to setup.mjs ────────────────────────────────
echo
echo "[3/3] Running universal setup script (setup.mjs)..."
echo
exec node "${REPO_ROOT}/setup.mjs" "$@"
