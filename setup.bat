@echo off
:: BizarreCRM Windows Gateway
:: ===========================
:: Thin gateway: verifies Node.js is installed at the required version,
:: tries to install it via winget if missing, falls back to opening the
:: Node.js download page in the operator's default browser. Then hands
:: off to the universal `setup.mjs` script which performs the actual
:: install/update flow.
::
:: This file is INTENTIONALLY MINIMAL. The bulk of the install logic
:: lives in setup.mjs (cross-platform) — see OPS-DEFERRED-001 in TODO.md
:: and docs/dashboard-migration-plan.md Phase C-pre.
::
:: For now, on Windows setup.mjs delegates back to scripts/setup-windows.bat
:: which is a copy of the original setup.bat logic. The split keeps the
:: gateway surface stable while the universal port is in progress.
::
:: Required Node version: 22.11+ (matches packages/server engines field).

setlocal enabledelayedexpansion
title BizarreCRM Install / Update
color 0B

set "ROOT=%~dp0"
set "REQUIRED_NODE_MAJOR=22"
set "NODE_DOWNLOAD_URL=https://nodejs.org/en/download/"

echo  ============================================
echo     BizarreCRM Setup ^(Windows Gateway^)
echo  ============================================
echo.

:: ── Step 1: Check Node.js ────────────────────────────────────────
echo  [1/3] Checking Node.js...
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo  Node.js not found.
    goto :try_install_node
)

:: Parse major version from `node --version` (e.g. v22.11.0 -> 22).
for /f "tokens=1,2,3 delims=v." %%a in ('node --version 2^>nul') do set "NODE_MAJOR=%%a"
if "%NODE_MAJOR%"=="" (
    echo  WARNING: Could not parse Node.js version. Proceeding anyway.
    goto :run_universal
)
if !NODE_MAJOR! LSS %REQUIRED_NODE_MAJOR% (
    echo  Node.js v!NODE_MAJOR! detected, but v%REQUIRED_NODE_MAJOR%+ required.
    goto :try_install_node
)
echo  OK - Node.js v!NODE_MAJOR! detected.
goto :run_universal

:: ── Step 2: Try to install Node.js ───────────────────────────────
:try_install_node
echo.
echo  [2/3] Attempting to install Node.js LTS via winget...
where winget >nul 2>&1
if %errorlevel% neq 0 (
    echo  winget not available on this machine.
    goto :open_download_page
)

:: Run winget. Accept package + source agreements non-interactively;
:: silent install. winget surfaces its own UAC prompt — operator must click
:: "Yes". If they decline, winget exits non-zero and we fall through to the
:: download page.
winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
if %errorlevel% neq 0 (
    echo  winget install failed or was declined.
    goto :open_download_page
)

:: winget installs Node into Program Files but does NOT update the current
:: shell's PATH for this session. Re-resolve `where node` after install; if
:: still missing, advise the operator to reopen the terminal.
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  Node.js installed, but this shell's PATH was not refreshed.
    echo  Close this window and re-run setup.bat from a NEW terminal.
    echo.
    pause
    exit /b 1
)
echo  OK - Node.js installed via winget.
goto :run_universal

:: ── Fallback: open the download page ─────────────────────────────
:open_download_page
echo.
echo  Could not install Node.js automatically.
echo  Opening the official Node.js download page in your browser.
echo  Install the LTS ^(v22 or newer^), then re-run setup.bat.
echo.
start "" "%NODE_DOWNLOAD_URL%"
echo  Press any key to exit.
pause >nul
exit /b 1

:: ── Step 3: Hand off to setup.mjs ────────────────────────────────
:run_universal
echo.
echo  [3/3] Running universal setup script ^(setup.mjs^)...
echo.
:: %* forwards any flags the operator passed to setup.bat (e.g. --skip-build).
node "%ROOT%setup.mjs" %*
exit /b %errorlevel%
