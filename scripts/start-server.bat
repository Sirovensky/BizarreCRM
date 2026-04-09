@echo off
setlocal

echo ============================================
echo  BizarreCRM Server
echo ============================================
echo.

:: Navigate to project root (one level up from scripts/)
cd /d "%~dp0.."

:: Check Node.js
where node >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Node.js is not installed. Download from https://nodejs.org/
    pause
    exit /b 1
)

:: Check dependencies
if not exist "node_modules" (
    echo Installing dependencies...
    call npm install
    if %ERRORLEVEL% neq 0 (
        echo ERROR: npm install failed.
        pause
        exit /b 1
    )
)

:: Build shared package if needed
if not exist "packages\shared\dist" (
    echo Building shared package...
    call npm run build --workspace=packages/shared
)

:: Check if PM2 is available
where pm2 >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo PM2 not found — starting server directly.
    echo Press Ctrl+C to stop.
    echo.
    cd packages\server
    npx tsx src/index.ts
) else (
    echo Starting server with PM2...
    call pm2 start ecosystem.config.js
    echo.
    echo Server started. Use "pm2 logs bizarre-crm" to view logs.
    echo Use "pm2 stop bizarre-crm" to stop.
    echo.
    call pm2 status
    pause
)
