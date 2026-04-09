@echo off
setlocal enabledelayedexpansion
title BizarreCRM Setup
color 0B

:: Save the root directory so we can always find files
set "ROOT=%~dp0"

echo.
echo  ======================================
echo    BizarreCRM - One-Click Setup
echo  ======================================
echo.

:: ── Step 1: Check Node.js ────────────────────────────────────────

echo  [1/7] Checking Node.js...
where node >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo.
    echo  ERROR: Node.js is not installed.
    echo.
    echo  Please install Node.js 22 LTS from:
    echo    https://nodejs.org/
    echo.
    echo  IMPORTANT: During install, check the box:
    echo    "Automatically install the necessary tools"
    echo    ^(this installs Python + C++ build tools^)
    echo.
    echo  After installing, close this window and run setup.bat again.
    echo.
    pause
    exit /b 1
)

for /f "tokens=1,2,3 delims=v." %%a in ('node --version') do set NODE_MAJOR=%%a
if !NODE_MAJOR! LSS 20 (
    color 0C
    echo  ERROR: Node.js 20+ required. You have v!NODE_MAJOR!.
    echo  Download the latest LTS from https://nodejs.org/
    pause
    exit /b 1
)
echo  OK - Node.js v!NODE_MAJOR! detected

:: ── Step 2: Install dependencies ─────────────────────────────────

echo.
echo  [2/7] Installing dependencies...
echo         (this may take 2-3 minutes on first run)
echo.
call npm install
if %errorlevel% neq 0 (
    color 0C
    echo.
    echo  ERROR: npm install failed.
    echo  If you see errors about Python or C++ build tools:
    echo    1. Open PowerShell as Administrator
    echo    2. Run: npm install -g windows-build-tools
    echo    3. Restart this setup script
    echo.
    pause
    exit /b 1
)
echo  OK - Dependencies installed

:: ── Step 3: Generate .env ────────────────────────────────────────

echo.
echo  [3/7] Setting up environment...

:: Ask for domain on first setup (only if .env doesn't exist yet)
if not exist "%ROOT%.env" (
    echo.
    echo  Enter your domain name for the CRM server.
    echo  Examples: bizarrecrm.com, myshop.com
    echo  Press Enter for local-only setup (localhost^).
    echo.
    set "USER_DOMAIN="
    set /p "USER_DOMAIN=  Domain: "
    if "!USER_DOMAIN!"=="" set "USER_DOMAIN=localhost"
)

node packages\server\scripts\generate-env.cjs !USER_DOMAIN!
if %errorlevel% neq 0 (
    color 0C
    echo  ERROR: Failed to generate .env
    pause
    exit /b 1
)

:: ── Step 4: Generate SSL certificates ────────────────────────────

echo.
echo  [4/7] Setting up SSL certificates...
node packages\server\scripts\generate-certs.cjs
if %errorlevel% neq 0 (
    color 0E
    echo  WARNING: Could not auto-generate SSL certs.
    echo  The server ships with self-signed dev certs that will still work.
    echo  For production, place your real certs in packages\server\certs\
    echo.
)

:: ── Copy Android APK if available ─────────────────────────────────
:: (pre-built APK or manually placed in packages/android/app/build/outputs/apk/)
if not exist "%ROOT%packages\server\downloads" mkdir "%ROOT%packages\server\downloads"
if exist "%ROOT%packages\android\app\build\outputs\apk\release\app-release.apk" (
    copy /Y "%ROOT%packages\android\app\build\outputs\apk\release\app-release.apk" "%ROOT%packages\server\downloads\BizarreCRM.apk" >nul
    echo  OK - Android APK copied to downloads folder (release)
) else if exist "%ROOT%packages\android\app\build\outputs\apk\debug\app-debug.apk" (
    copy /Y "%ROOT%packages\android\app\build\outputs\apk\debug\app-debug.apk" "%ROOT%packages\server\downloads\BizarreCRM.apk" >nul
    echo  OK - Android APK copied to downloads folder (debug)
) else (
    echo  No Android APK found. Place it at packages\server\downloads\BizarreCRM.apk manually.
)

:: ── Step 5: Build frontend ───────────────────────────────────────

echo.
echo  [5/7] Building frontend...
echo         (compiling React app for production)
echo.
call npm run build
if %errorlevel% neq 0 (
    color 0C
    echo.
    echo  ERROR: Build failed. Check the output above for details.
    pause
    exit /b 1
)
echo  OK - Frontend built

:: ── Step 6: Build Management Dashboard ───────────────────────────

echo.
echo  [6/7] Building Management Dashboard...
echo         (compiling Electron app)
echo.
pushd "%ROOT%packages\management"
call npm run build
if %errorlevel% neq 0 (
    color 0E
    echo  WARNING: Dashboard build failed. Server will still work.
    echo  You can build the dashboard later with:
    echo    cd packages\management ^&^& npm run build ^&^& npm run package
    echo.
) else (
    echo  OK - Dashboard built
    echo  Packaging dashboard EXE...
    call npm run package 2>nul
    if %errorlevel% equ 0 (
        echo  OK - Dashboard EXE packaged
        :: Copy to root dashboard/ folder for easy access
        if exist "release\win-unpacked\BizarreCRM Management.exe" (
            if exist "%ROOT%dashboard" rmdir /s /q "%ROOT%dashboard" 2>nul
            xcopy /E /I /Q /Y "release\win-unpacked" "%ROOT%dashboard" >nul 2>nul
            echo  OK - Copied to dashboard\ folder
        )
    ) else (
        echo  WARNING: Dashboard packaging failed. You can run it with:
        echo    cd packages\management ^&^& npm start
    )
)
popd

:: ── Step 7: Launch dashboard ─────────────────────────────────────
:: The dashboard auto-starts the server, so we just need to launch the EXE.

echo.
echo  [7/7] Launching...
echo.

color 0A
echo  ============================================
echo.
echo     Setup Complete!
echo.
echo  ============================================
echo.

:: Launch dashboard EXE
if exist "%ROOT%dashboard\BizarreCRM Management.exe" (
    echo  Starting Management Dashboard...
    start "" "%ROOT%dashboard\BizarreCRM Management.exe"
    echo  Dashboard launched. It will start the server automatically.
) else if exist "%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe" (
    echo  Starting Management Dashboard...
    start "" "%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe"
    echo  Dashboard launched. It will start the server automatically.
) else (
    echo  Dashboard EXE not found. Starting server directly...
    start "BizarreCRM Server" cmd /k "cd /d "%ROOT%packages\server" && npx tsx src/index.ts"
    echo  Server starting. Open https://localhost:443 in your browser.
)

echo.
echo  Setup window will close in 5 seconds...
timeout /t 5 /nobreak >nul
