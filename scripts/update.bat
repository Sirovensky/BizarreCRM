@echo off
setlocal enabledelayedexpansion
title BizarreCRM Update
color 0B
set "ROOT=%~dp0.."
cd /d "%ROOT%"

echo.
echo  ======================================
echo    BizarreCRM — Updating...
echo  ======================================
echo.

:: Step 1: Pull latest code
echo  [1/5] Pulling latest code...
git pull origin main
if %errorlevel% neq 0 (
    color 0C
    echo  ERROR: git pull failed.
    pause
    exit /b 1
)
echo  OK

:: Step 2: Kill everything
echo.
echo  [2/5] Stopping server and dashboard...
taskkill /F /IM "BizarreCRM Management.exe" >nul 2>&1
taskkill /F /IM node.exe >nul 2>&1
timeout /t 3 /nobreak >nul
echo  OK

:: Step 3: Install deps + build
echo.
echo  [3/5] Installing dependencies...
call npm install
echo.
echo  [4/5] Building everything...
call npm run build
if %errorlevel% neq 0 (
    color 0C
    echo  ERROR: Build failed.
    pause
    exit /b 1
)

:: Build + package dashboard
pushd packages\management
call npm run build
call npm run package 2>nul
if exist "release\win-unpacked" (
    if exist "%ROOT%\dashboard" rmdir /s /q "%ROOT%\dashboard" 2>nul
    xcopy /E /I /Q /Y "release\win-unpacked" "%ROOT%\dashboard" >nul 2>nul
    echo  OK - Dashboard rebuilt
)
popd

:: Step 5: Launch dashboard (which auto-starts server)
echo.
echo  [5/5] Launching dashboard...

set "DASHBOARD="
if exist "%ROOT%\dashboard\BizarreCRM Management.exe" set "DASHBOARD=%ROOT%\dashboard\BizarreCRM Management.exe"
if not defined DASHBOARD if exist "%ROOT%\packages\management\release\win-unpacked\BizarreCRM Management.exe" set "DASHBOARD=%ROOT%\packages\management\release\win-unpacked\BizarreCRM Management.exe"

if defined DASHBOARD (
    start "" "!DASHBOARD!"
) else (
    echo  Dashboard EXE not found. Starting server directly...
    start "BizarreCRM Server" cmd /k "cd /d "%ROOT%\packages\server" && npx tsx src/index.ts"
)

color 0A
echo.
echo  ======================================
echo    Update Complete!
echo  ======================================
echo.
echo  Press any key to close this window.
pause
