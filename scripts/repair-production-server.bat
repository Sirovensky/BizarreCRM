@echo off
setlocal enabledelayedexpansion

title BizarreCRM Production Server Repair
set "ROOT=%~dp0.."
cd /d "%ROOT%"

echo.
echo ============================================
echo  BizarreCRM Production Server Repair
echo ============================================
echo.
echo This rebuilds the server artifacts PM2 runs, verifies SQL migrations
echo were copied into dist, clears stale PM2 state, starts bizarre-crm,
echo and runs the health check.
echo.

if not exist "package.json" (
  echo ERROR: Run this from the BizarreCRM repo. Expected package.json at:
  echo   %CD%\package.json
  pause
  exit /b 1
)

echo [1/7] Pulling latest code from GitHub...
where git >nul 2>&1
if %ERRORLEVEL% equ 0 (
  git pull origin main
  if !ERRORLEVEL! neq 0 (
    echo ERROR: git pull failed. Resolve the Git error above, then rerun this script.
    pause
    exit /b 1
  )
) else (
  echo Git was not found on PATH. Skipping pull.
)
echo.

echo [2/7] Checking Node.js, npm, and PM2...
where node >nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo ERROR: Node.js is not installed or is not on PATH.
  pause
  exit /b 1
)
where npm.cmd >nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo ERROR: npm.cmd is not on PATH.
  pause
  exit /b 1
)
where pm2.cmd >nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo ERROR: pm2.cmd is not on PATH. Install it with:
  echo   npm.cmd install -g pm2
  pause
  exit /b 1
)
node --version
call npm.cmd --version
call pm2.cmd --version
echo.

echo [3/7] Installing dependencies...
call npm.cmd install
if %ERRORLEVEL% neq 0 (
  echo ERROR: npm install failed.
  pause
  exit /b 1
)
echo.

echo [4/7] Building shared, web, and server packages...
call npm.cmd run build
if %ERRORLEVEL% neq 0 (
  echo ERROR: npm run build failed.
  pause
  exit /b 1
)
echo.

echo [5/7] Verifying compiled server artifacts...
if not exist "packages\server\dist\index.js" (
  echo ERROR: packages\server\dist\index.js is missing after build.
  pause
  exit /b 1
)
if not exist "packages\server\dist\db\migrations" (
  echo ERROR: packages\server\dist\db\migrations is missing after build.
  pause
  exit /b 1
)
for /f %%C in ('dir /b "packages\server\dist\db\migrations\*.sql" 2^>nul ^| find /c /v ""') do set "MIGRATION_COUNT=%%C"
if "!MIGRATION_COUNT!"=="0" (
  echo ERROR: No SQL migrations were copied into dist\db\migrations.
  pause
  exit /b 1
)
if not exist "logs" mkdir "logs"
echo OK - Found !MIGRATION_COUNT! compiled SQL migration files.
echo.

echo [6/7] Restarting PM2 app...
call pm2.cmd delete bizarre-crm >nul 2>&1
call pm2.cmd start ecosystem.config.js --update-env
if %ERRORLEVEL% neq 0 (
  echo ERROR: PM2 failed to start bizarre-crm.
  echo Showing recent PM2 logs:
  call pm2.cmd logs bizarre-crm --lines 80 --nostream
  pause
  exit /b 1
)
call pm2.cmd save
call pm2.cmd status
echo.

echo [7/7] Running health check...
node scripts\health-check.cjs
set "HEALTH_EXIT=%ERRORLEVEL%"
echo.
if not "%HEALTH_EXIT%"=="0" (
  echo Health check still reports issues. Read the "Issues to fix" section above.
  pause
  exit /b %HEALTH_EXIT%
)

echo Production server repair completed successfully.
pause
exit /b 0
