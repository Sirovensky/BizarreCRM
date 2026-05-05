#!/usr/bin/env bash
# BizarreCRM Linux / macOS-terminal Gateway
# ==========================================
# Thin gateway: verifies Node.js >= v22 is on PATH, tries to install via
# the host's package manager if missing, falls back to opening nodejs.org.
# Then exec's the universal setup.mjs script.
#
# Detected package managers (best effort):
#   - apt-get      Debian / Ubuntu / Mint      → uses NodeSource setup_22.x
#   - dnf / yum    Fedora / RHEL / CentOS      → uses NodeSource setup_22.x
#   - pacman       Arch / Manjaro              → `pacman -S nodejs npm`
#   - zypper       openSUSE                    → `zypper install nodejs22`
#   - apk          Alpine                      → `apk add --update nodejs npm`
#   - brew         macOS (terminal users; setup.command preferred for Finder)
#
# Falls through to xdg-open / open of the Node.js download page if the
# host's package manager is unrecognized OR the install is declined.
#
# Auto-install requires sudo on most distros — we PRINT the command and
# ask for confirmation before invoking sudo. Operators in CI / unattended
# contexts can pre-install Node and skip this script's install branch.
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
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${NODE_DOWNLOAD_URL}" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open "${NODE_DOWNLOAD_URL}" >/dev/null 2>&1 || true
  else
    echo "No browser-opener tool found. Visit ${NODE_DOWNLOAD_URL} manually."
  fi
  read -rp "Press Enter to exit..."
  exit 1
}

# Prompt the operator before running a sudo command. On CI / unattended
# environments the prompt lands on stdin and the operator has no way to
# answer — exit non-zero so wrapping scripts can detect the bail-out.
confirm_sudo() {
  local cmd="$1"
  echo
  echo "About to run as root:"
  echo "  $cmd"
  echo
  if [[ ! -t 0 ]]; then
    echo "stdin is not a TTY — cannot prompt. Re-run interactively, or"
    echo "pre-install Node.js >= v${REQUIRED_NODE_MAJOR} and re-run."
    exit 1
  fi
  read -rp "Proceed? [y/N] " yn
  case "$yn" in
    [Yy]*) return 0 ;;
    *)     echo "Declined."; return 1 ;;
  esac
}

echo "============================================"
echo "   BizarreCRM Setup (Linux/macOS Gateway)"
echo "============================================"
echo

# ── Step 1: Check Node.js ────────────────────────────────────────
echo "[1/3] Checking Node.js..."
NODE_OK=0
if command -v node >/dev/null 2>&1; then
  NODE_VERSION="$(node --version 2>/dev/null || true)"
  NODE_MAJOR="${NODE_VERSION#v}"
  NODE_MAJOR="${NODE_MAJOR%%.*}"
  if [[ -n "${NODE_MAJOR}" && "${NODE_MAJOR}" =~ ^[0-9]+$ && "${NODE_MAJOR}" -ge "${REQUIRED_NODE_MAJOR}" && "${NODE_MAJOR}" -lt "${REJECTED_NODE_MAJOR}" ]]; then
    echo "OK - Node.js ${NODE_VERSION} detected."
    NODE_OK=1
  elif [[ -n "${NODE_MAJOR}" && "${NODE_MAJOR}" -ge "${REJECTED_NODE_MAJOR}" ]]; then
    # Node too new: fall through to the install branch below. NodeSource
    # setup_22.x replaces the apt repo source list and `apt-get install
    # nodejs` then downgrades to v22. brew on macOS/Linuxbrew uses
    # `brew unlink node && brew link node@22` (handled in the install
    # branch). pacman/zypper/apk track their distro's current Node
    # version and may not be able to downgrade — fallback to download
    # page if so.
    echo "Node.js ${NODE_VERSION} detected, but repo engines require Node 22-24."
    echo "Attempting to install Node 22 LTS via host package manager..."
    NODE_OK=0
  else
    echo "Node.js ${NODE_VERSION:-(unknown)} detected, but v${REQUIRED_NODE_MAJOR}+ required."
  fi
else
  echo "Node.js not found."
fi

# ── Step 2: Try to install Node.js via host package manager ──────
if [[ "${NODE_OK}" -eq 0 ]]; then
  echo
  echo "[2/3] Detecting host package manager..."

  INSTALLED=0

  # NB: `set -e` is active. Each install branch must NOT exit on a failed
  # install command — instead set INSTALLED=0 and fall through to the
  # `if [[ INSTALLED -ne 1 ]]; open_download_page` fallback below. The
  # `||` operator short-circuits and prevents `set -e` from firing.
  if command -v apt-get >/dev/null 2>&1; then
    echo "Detected apt-get (Debian/Ubuntu)."
    # NodeSource is the upstream-blessed install path for Debian/Ubuntu.
    # Two-step: register the NodeSource apt repo, then `apt-get install nodejs`.
    if confirm_sudo "curl -fsSL https://deb.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x | sudo bash - && sudo apt-get install -y nodejs"; then
      { curl -fsSL "https://deb.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | sudo bash - && sudo apt-get install -y nodejs; } && INSTALLED=1 || INSTALLED=0
    fi
  elif command -v dnf >/dev/null 2>&1; then
    echo "Detected dnf (Fedora/RHEL)."
    if confirm_sudo "curl -fsSL https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x | sudo bash - && sudo dnf install -y nodejs"; then
      { curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | sudo bash - && sudo dnf install -y nodejs; } && INSTALLED=1 || INSTALLED=0
    fi
  elif command -v yum >/dev/null 2>&1; then
    echo "Detected yum (older RHEL/CentOS)."
    if confirm_sudo "curl -fsSL https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x | sudo bash - && sudo yum install -y nodejs"; then
      { curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | sudo bash - && sudo yum install -y nodejs; } && INSTALLED=1 || INSTALLED=0
    fi
  elif command -v pacman >/dev/null 2>&1; then
    echo "Detected pacman (Arch/Manjaro)."
    if confirm_sudo "sudo pacman -S --noconfirm nodejs npm"; then
      sudo pacman -S --noconfirm nodejs npm && INSTALLED=1 || INSTALLED=0
    fi
  elif command -v zypper >/dev/null 2>&1; then
    echo "Detected zypper (openSUSE)."
    if confirm_sudo "sudo zypper install -y nodejs${REQUIRED_NODE_MAJOR}"; then
      sudo zypper install -y "nodejs${REQUIRED_NODE_MAJOR}" && INSTALLED=1 || INSTALLED=0
    fi
  elif command -v apk >/dev/null 2>&1; then
    echo "Detected apk (Alpine)."
    if confirm_sudo "sudo apk add --update nodejs npm"; then
      sudo apk add --update nodejs npm && INSTALLED=1 || INSTALLED=0
    fi
  elif command -v brew >/dev/null 2>&1; then
    echo "Detected Homebrew (macOS terminal install)."
    if brew install "node@${REQUIRED_NODE_MAJOR}"; then
      # Unlink any existing `node` formula (e.g. v25 currently linked) so
      # link --overwrite --force doesn't fight a peer formula. Failures
      # are tolerable; `command -v node` below is the source of truth.
      brew unlink node 2>/dev/null || true
      brew link --overwrite --force "node@${REQUIRED_NODE_MAJOR}" || true
      INSTALLED=1
    fi
  else
    echo "No supported package manager detected."
  fi

  if [[ "${INSTALLED}" -ne 1 ]]; then
    open_download_page
  fi

  # Verify Node landed on PATH after install. Some distro installs require
  # a shell restart to refresh the hash table; tell the operator if so.
  hash -r 2>/dev/null || true
  if ! command -v node >/dev/null 2>&1; then
    echo
    echo "Node.js installed, but this shell's PATH was not refreshed."
    echo "Close this terminal and re-run setup from a NEW terminal."
    read -rp "Press Enter to exit..."
    exit 1
  fi
  echo "OK - Node.js installed."
fi

# ── Step 3: Hand off to setup.mjs ────────────────────────────────
echo
echo "[3/3] Running universal setup script (setup.mjs)..."
echo
exec node "${REPO_ROOT}/setup.mjs" "$@"
