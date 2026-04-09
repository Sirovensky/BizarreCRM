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
node packages\server\scripts\generate-env.cjs
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

:: ── Step 7: Start server ─────────────────────────────────────────

echo.
echo  [7/7] Starting BizarreCRM server...
echo.

:: Check if PM2 is available
where pm2 >nul 2>&1
if %errorlevel% equ 0 (
    echo  Starting with PM2 (auto-restart on crash)...
    call pm2 start ecosystem.config.js --name bizarre-crm 2>nul
    call pm2 save 2>nul
    echo  OK - Server running via PM2
    echo.
    echo  Useful PM2 commands:
    echo    pm2 logs bizarre-crm    View live logs
    echo    pm2 restart bizarre-crm Restart server
    echo    pm2 stop bizarre-crm    Stop server
) else (
    echo  Starting server directly...
    echo  (Install PM2 for auto-restart: npm install -g pm2)
    echo.
    start "BizarreCRM Server" cmd /k "cd packages\server && npx tsx src/index.ts"
)

:: ── Wait for server to be ready ──────────────────────────────────

echo.
echo  Waiting for server to start...
set READY=0
for /L %%i in (1,1,30) do (
    if !READY! equ 0 (
        timeout /t 2 /nobreak >nul
        curl -sk https://localhost:443/api/v1/info >nul 2>&1
        if !errorlevel! equ 0 (
            set READY=1
        ) else (
            <nul set /p="."
        )
    )
)

if !READY! equ 0 (
    color 0E
    echo.
    echo.
    echo  WARNING: Server may still be starting up.
    echo  Check the server window for errors, then open
    echo  https://localhost:443 in your browser manually.
    echo.
    pause
    exit /b 0
)

:: ── Success ─────────────────────────────────────────────────────

color 0A
echo.
echo.
echo  ============================================
echo.
echo     Setup Complete - Server is Running!
echo.
echo  ============================================
echo.
echo  Login:     admin / admin123
echo             (change password on first login)
echo.

:: Open the CRM in the default browser
echo  Opening BizarreCRM in your browser...
start "" "https://localhost:443"

:: Launch the dashboard EXE
set "DASHBOARD="
if exist "%ROOT%dashboard\BizarreCRM Management.exe" (
    set "DASHBOARD=%ROOT%dashboard\BizarreCRM Management.exe"
) else if exist "%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe" (
    set "DASHBOARD=%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe"
)

if defined DASHBOARD (
    echo  Launching Management Dashboard...
    start "" "!DASHBOARD!"
) else (
    echo  Dashboard EXE not found. You can run it with:
    echo    cd packages\management ^&^& npm start
)

echo.
echo  Press any key to close this window.
echo  (The server keeps running in the background)
echo.
pause
