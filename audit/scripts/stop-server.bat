@echo off
setlocal

echo ============================================
echo  BizarreCRM Server — Stop
echo ============================================
echo.

:: Try PM2 first
where pm2 >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo Stopping via PM2...
    call pm2 stop bizarre-crm 2>nul
    call pm2 delete bizarre-crm 2>nul
    echo PM2 process stopped.
    echo.
)

:: Kill any node processes running the CRM server
echo Stopping all Node.js server processes...
taskkill /F /FI "WINDOWTITLE eq BizarreCRM Server" >nul 2>&1
taskkill /F /IM node.exe >nul 2>&1

echo.
echo Server stopped.
echo.
pause
