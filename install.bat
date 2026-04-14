@echo off
setlocal enabledelayedexpansion
title BizarreCRM Install / Update
color 0B

:: Save the root directory so we can always find files
set "ROOT=%~dp0"
cd /d "%ROOT%"

echo.
echo  ======================================
echo    BizarreCRM - Install / Update
echo  ======================================
echo.

:: ── Step 1: Pull latest code (if git is configured) ──────────────
echo  [1/9] Pulling latest code...
:: Only reset package-lock.json so npm can handle updates cleanly.
git checkout -- package-lock.json >nul 2>&1
git pull origin main >nul 2>&1
echo  OK
echo.

:: ── Step 2: Stop running instances ───────────────────────────────
echo  [2/9] Stopping running servers and dashboard...
taskkill /F /IM "BizarreCRM Management.exe" >nul 2>&1
taskkill /F /IM node.exe >nul 2>&1
:: Short wait for processes to fully exit and free up ports
timeout /t 3 /nobreak >nul
echo  OK - Processes stopped
echo.

:: ── Step 3: Check Node.js ────────────────────────────────────────
echo  [3/9] Checking Node.js...
where node >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo.
    echo  ERROR: Node.js is not installed.
    echo  Please install Node.js 22 LTS from: https://nodejs.org/
    pause
    exit /b 1
)

for /f "tokens=1,2,3 delims=v." %%a in ('node --version') do set NODE_MAJOR=%%a
if !NODE_MAJOR! LSS 20 (
    color 0C
    echo  ERROR: Node.js 20+ required. You have v!NODE_MAJOR!.
    pause
    exit /b 1
)
echo  OK - Node.js v!NODE_MAJOR! detected
echo.

:: ── Step 4: Install dependencies ─────────────────────────────────
echo  [4/9] Installing dependencies...
call npm install
if %errorlevel% neq 0 (
    color 0C
    echo  ERROR: npm install failed.
    pause
    exit /b 1
)
echo  OK - Dependencies installed
echo.

:: ── Step 5: Setup Configuration ──────────────────────────────────
echo  [5/9] Setting up configuration...
if not exist "%ROOT%.env" (
    echo.
    echo  Enter your domain name for the CRM server.
    echo  Examples: bizarrecrm.com, myshop.com
    echo  Press Enter for local-only setup (localhost^).
    echo.
    set "USER_DOMAIN="
    set /p "USER_DOMAIN=  Domain: "
    if "!USER_DOMAIN!"=="" set "USER_DOMAIN=localhost"
    
    node packages\server\scripts\generate-env.cjs !USER_DOMAIN!
) else (
    echo  .env already exists, skipping generation.
)
echo.

:: ── Step 6: Generate SSL certificates ────────────────────────────
echo  [6/9] Setting up SSL certificates...
if not exist "%ROOT%packages\server\certs\server.cert" (
    node packages\server\scripts\generate-certs.cjs
) else (
    echo  SSL certificates already exist.
)
echo.

:: ── Copy Android APK if available ─────────────────────────────────
if not exist "%ROOT%packages\server\downloads" mkdir "%ROOT%packages\server\downloads"
if exist "%ROOT%packages\android\app\build\outputs\apk\release\app-release.apk" (
    copy /Y "%ROOT%packages\android\app\build\outputs\apk\release\app-release.apk" "%ROOT%packages\server\downloads\BizarreCRM.apk" >nul
) else if exist "%ROOT%packages\android\app\build\outputs\apk\debug\app-debug.apk" (
    copy /Y "%ROOT%packages\android\app\build\outputs\apk\debug\app-debug.apk" "%ROOT%packages\server\downloads\BizarreCRM.apk" >nul
)

:: ── Step 7: Build Application ────────────────────────────────────
echo  [7/9] Building Application...
call npm run build
if %errorlevel% neq 0 (
    color 0C
    echo  ERROR: Build failed. Check the output above for details.
    pause
    exit /b 1
)

:: Copy non-TS worker files that tsc doesn't emit (piscina worker pool)
copy /Y "%ROOT%packages\server\src\db\db-worker.mjs" "%ROOT%packages\server\dist\db\db-worker.mjs" >nul 2>&1
echo  OK - Build completed
echo.

:: ── Step 8: Build Management Dashboard ───────────────────────────
echo  [8/9] Building Management Dashboard...
pushd "%ROOT%packages\management"
call npm run build
call npm run package >nul 2>&1
if exist "release\win-unpacked" (
    if exist "%ROOT%dashboard" rmdir /s /q "%ROOT%dashboard" 2>nul
    xcopy /E /I /Q /Y "release\win-unpacked" "%ROOT%dashboard" >nul 2>nul
    echo  OK - Dashboard built
)
popd
echo.

:: ── Step 9: Launch ───────────────────────────────────────────────
echo  [9/9] Launching...
echo.

color 0A
echo  ============================================
echo.
echo     Install / Update Complete!
echo.
echo  ============================================
echo.

set "DASHBOARD="
if exist "%ROOT%dashboard\BizarreCRM Management.exe" set "DASHBOARD=%ROOT%dashboard\BizarreCRM Management.exe"
if not defined DASHBOARD if exist "%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe" set "DASHBOARD=%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe"

if defined DASHBOARD (
    start "" "!DASHBOARD!"
    echo  Dashboard launched. It will start the server automatically.
) else (
    echo  Dashboard EXE not found. Starting server directly...
    start "BizarreCRM Server" cmd /k "cd /d "%ROOT%packages\server" && npx tsx src/index.ts"
)

endlocal
exit
