@echo off
setlocal

echo ============================================
echo  BizarreCRM Server — Stop
echo ============================================
echo.

where pm2 >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo PM2 not found. Kill the server from Task Manager (node.exe).
    pause
    exit /b 1
)

call pm2 stop bizarre-crm
echo.
echo Server stopped.
pause
