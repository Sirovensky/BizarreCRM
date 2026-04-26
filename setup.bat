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
echo  [1/10] Pulling latest code...
:: Only reset package-lock.json so npm can handle updates cleanly.
:: NEVER reset: .env, *.db, uploads/, certs/, data/ — those are protected by .gitignore
git checkout -- package-lock.json >nul 2>&1
git pull origin main >nul 2>&1
echo  OK
echo.

:: ── Step 2: Stop running instances ───────────────────────────────
echo  [2/10] Stopping running servers and dashboard...
taskkill /F /IM "BizarreCRM Management.exe" >nul 2>&1
taskkill /F /IM node.exe >nul 2>&1
:: Wait for processes to fully exit and free up ports
timeout /t 3 /nobreak >nul
echo  OK - Processes stopped
echo.

:: ── Step 3: Check Node.js ────────────────────────────────────────
echo  [3/10] Checking Node.js...
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
echo.

:: ── Ensure npm global tools are available on PATH ─────────────────
:: npm global command shims such as pm2.cmd usually live in %APPDATA%\npm,
:: but npm config get prefix is the source of truth if the user changed it.
set "NPM_GLOBAL_PREFIX="
if defined APPDATA call :EnsureUserPath "%APPDATA%\npm"
for /f "delims=" %%P in ('npm config get prefix 2^>nul') do (
    if not defined NPM_GLOBAL_PREFIX set "NPM_GLOBAL_PREFIX=%%P"
)
if defined NPM_GLOBAL_PREFIX if /I not "!NPM_GLOBAL_PREFIX!"=="undefined" call :EnsureUserPath "!NPM_GLOBAL_PREFIX!"
echo.

:: ── Step 4: Install dependencies ─────────────────────────────────
echo  [4/10] Installing dependencies...
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
echo.

:: ── Step 5: Setup Configuration ──────────────────────────────────
:: generate-env.cjs is idempotent: on a missing .env it does a fresh
:: install; on an existing .env it APPENDS any new sections added since
:: the prior install (JWT_SECRET, UPLOADS_SECRET, BACKUP_ENCRYPTION_KEY,
:: etc.). Running it every setup.bat pass means new FATAL-in-prod config
:: gates (SEC-H54 UPLOADS_SECRET, PROD54 BACKUP_ENCRYPTION_KEY, SA1-1
:: JWT_SECRET_PREVIOUS pattern, etc.) get auto-filled on upgrade instead
:: of crash-looping pm2 after `git pull`.
echo  [5/10] Setting up configuration...
if not exist "%ROOT%.env" (
    echo.
    echo  Enter your domain name for the CRM server.
    echo  Examples: example.com, myshop.com
    echo  Press Enter for local-only setup (localhost^).
    echo.
    set "USER_DOMAIN="
    set /p "USER_DOMAIN=  Domain: "
    if "!USER_DOMAIN!"=="" set "USER_DOMAIN=localhost"

    node packages\server\scripts\generate-env.cjs !USER_DOMAIN!
    if !errorlevel! neq 0 (
        color 0C
        echo  ERROR: Failed to generate .env
        pause
        exit /b 1
    )
) else (
    echo  .env exists — checking for missing sections after upgrade...
    node packages\server\scripts\generate-env.cjs
    if !errorlevel! neq 0 (
        color 0E
        echo  WARNING: Could not verify .env sections. Continuing anyway.
    )
)
node packages\server\scripts\ensure-env-secrets.cjs
if !errorlevel! neq 0 (
    color 0C
    echo  ERROR: Failed to generate secure .env auth secrets
    pause
    exit /b 1
)
echo.

:: ── Step 6: Generate SSL certificates ────────────────────────────
echo  [6/10] Setting up SSL certificates...
if not exist "%ROOT%packages\server\certs\server.cert" (
    node packages\server\scripts\generate-certs.cjs
    if !errorlevel! neq 0 (
        color 0E
        echo  WARNING: Could not auto-generate SSL certs.
        echo  The server ships with self-signed dev certs that will still work.
        echo  For production, place your real certs in packages\server\certs\
        echo.
    )
) else (
    echo  SSL certificates already exist.
)
echo.

:: ── Step 7: Build Android APK (if SDK is installed) ──────────────
echo  [7/10] Checking Android SDK for Mobile App build...
if defined ANDROID_HOME (
    echo  Android SDK found. Building APK...
    pushd "%ROOT%android"
    call gradlew.bat assembleRelease >nul 2>&1
    if !errorlevel! neq 0 (
        color 0E
        echo  WARNING: Android APK build failed. The mobile app will not be updated.
    ) else (
        echo  OK - Android APK built successfully.
    )
    popd
) else if defined ANDROID_SDK_ROOT (
    echo  Android SDK found. Building APK...
    pushd "%ROOT%android"
    call gradlew.bat assembleRelease >nul 2>&1
    if !errorlevel! neq 0 (
        color 0E
        echo  WARNING: Android APK build failed. The mobile app will not be updated.
    ) else (
        echo  OK - Android APK built successfully.
    )
    popd
) else (
    echo  Android SDK not detected. Skipping Android APK build.
)
echo.

:: ── Copy Android APK if available ─────────────────────────────────
if not exist "%ROOT%packages\server\downloads" mkdir "%ROOT%packages\server\downloads"
if exist "%ROOT%android\app\build\outputs\apk\release\app-release.apk" (
    copy /Y "%ROOT%android\app\build\outputs\apk\release\app-release.apk" "%ROOT%packages\server\downloads\BizarreCRM.apk" >nul
    echo  OK - Android APK copied to downloads folder ^(release^)
) else if exist "%ROOT%android\app\build\outputs\apk\debug\app-debug.apk" (
    copy /Y "%ROOT%android\app\build\outputs\apk\debug\app-debug.apk" "%ROOT%packages\server\downloads\BizarreCRM.apk" >nul
    echo  OK - Android APK copied to downloads folder ^(debug^)
) else (
    echo  No Android APK found. Place it at packages\server\downloads\BizarreCRM.apk manually.
)

:: ── Step 8: Build Application ────────────────────────────────────
echo.
echo  [8/10] Building Application...
call npm run build
if %errorlevel% neq 0 (
    color 0C
    echo.
    echo  ERROR: Build failed. Check the output above for details.
    pause
    exit /b 1
)

:: Copy non-TS worker files that tsc doesn't emit (piscina worker pool)
copy /Y "%ROOT%packages\server\src\db\db-worker.mjs" "%ROOT%packages\server\dist\db\db-worker.mjs" >nul 2>&1
echo  OK - Build completed
echo.

:: ── Step 9: Build Management Dashboard ───────────────────────────
echo  [9/10] Building Management Dashboard...
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
    call npm run package >nul 2>&1
    :: Copy unpacked EXE to dashboard/ whether or not NSIS installer succeeded
    :: (the dir target produces win-unpacked even if signing/NSIS fails)
    if exist "release\win-unpacked\BizarreCRM Management.exe" (
        if exist "%ROOT%dashboard" rmdir /s /q "%ROOT%dashboard" 2>nul
        xcopy /E /I /Q /Y "release\win-unpacked" "%ROOT%dashboard" >nul 2>nul
        echo  OK - Dashboard EXE packaged
    ) else (
        echo  WARNING: Dashboard packaging failed. You can run it with:
        echo    cd packages\management ^&^& npm start
    )
)
popd
echo.

:: ── Step 10: Launch ───────────────────────────────────────────────
echo  [10/10] Launching...
echo.

color 0A
echo  ============================================
echo.
echo     Install / Update Complete!
echo.
echo  ============================================
echo.

:: ── Launch ───────────────────────────────────────────────────────
:: Key fix: ecosystem.config.js sets `wait_ready: true` with a 600s
:: listen_timeout, so a synchronous `pm2 start` in this script would
:: block for up to 10 minutes on a cold migration-heavy boot. Running
:: PM2 in a detached window lets the dashboard open immediately while
:: the server finishes warming up; errors surface in the PM2 window
:: rather than being swallowed by `>nul 2>&1`.
where pm2 >nul 2>&1
if %errorlevel% equ 0 (
    echo  Starting server via PM2 in a new window...
    :: Clear any stale pm2 entry from a previous failed run so `start`
    :: doesn't error out with "already launched". `pm2 delete` is a
    :: no-op if the app isn't registered.
    call pm2 delete bizarre-crm >nul 2>&1
    start "BizarreCRM Server (PM2)" /min cmd /c "pm2 start "%ROOT%ecosystem.config.js" --update-env & pm2 logs bizarre-crm --lines 0"
    echo  OK - PM2 window launched; server will be live on https://localhost once warm.
) else (
    echo  PM2 not found - starting server directly...
    start "BizarreCRM Server" /min cmd /c "cd /d "%ROOT%packages\server" && node dist\index.js"
    echo  OK - Server started directly
)
echo.

set "DASHBOARD="
if exist "%ROOT%dashboard\BizarreCRM Management.exe" set "DASHBOARD=%ROOT%dashboard\BizarreCRM Management.exe"
if not defined DASHBOARD if exist "%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe" set "DASHBOARD=%ROOT%packages\management\release\win-unpacked\BizarreCRM Management.exe"

if defined DASHBOARD (
    echo  Starting Management Dashboard...
    :: Launch dashboard detached so we never block on it. The dashboard
    :: probes the server on startup; if PM2 hasn't finished warming yet
    :: the dashboard shows a "connecting" state, not a crash.
    start "" "!DASHBOARD!"
    echo  OK - Dashboard launched.
) else (
    echo  Dashboard EXE not found. Server is running at https://localhost
)

endlocal
exit /b 0

:EnsureUserPath
set "PATH_DIR=%~1"
if not defined PATH_DIR exit /b 0
echo ;!PATH!; | find /I ";!PATH_DIR!;" >nul
if !errorlevel! neq 0 (
    echo  Adding npm global tools to PATH: !PATH_DIR!
    set "PATH=!PATH!;!PATH_DIR!"
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$dir = '%PATH_DIR%'.TrimEnd('\'); $userPath = [Environment]::GetEnvironmentVariable('Path', 'User'); $parts = @(); if ($userPath) { $parts = $userPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') } }; if ($parts -notcontains $dir) { $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $dir } else { $userPath.TrimEnd(';') + ';' + $dir }; [Environment]::SetEnvironmentVariable('Path', $newPath, 'User') }" >nul 2>&1
exit /b 0
