@echo off
setlocal

:: Request admin privileges
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================
echo  BizarreCRM Dashboard Builder
echo ============================================
echo.

:: Navigate to project root (one level up from scripts/)
cd /d "%~dp0.."

:: Step 0: Check prerequisites
echo [0/4] Checking prerequisites...

where node >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Node.js is not installed. Download from https://nodejs.org/
    pause
    exit /b 1
)
echo   Node.js: OK

where npm >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: npm is not installed.
    pause
    exit /b 1
)
echo   npm: OK

:: Install PM2 globally if not present (may need admin — warn if it fails)
where pm2 >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo   PM2: not found, installing globally...
    echo   (If this fails, run "npm install -g pm2" in an Administrator terminal^)
    call npm install -g pm2 2>nul
    where pm2 >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo   WARNING: PM2 install failed. Run as Administrator later: npm install -g pm2
        echo   Continuing without PM2...
    ) else (
        echo   PM2: installed
    )
) else (
    echo   PM2: OK
)

:: Step 1: Install dependencies if needed
if not exist "node_modules" (
    echo.
    echo [1/4] Installing dependencies...
    call npm install
    if %ERRORLEVEL% neq 0 (
        echo ERROR: npm install failed.
        pause
        exit /b 1
    )
) else (
    echo.
    echo [1/4] Dependencies already installed, skipping...
)

:: Step 2: Build management package
echo.
echo [2/4] Building dashboard (main + preload + renderer)...
call npm run build --workspace=packages/management
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Build failed. Check the output above.
    pause
    exit /b 1
)

:: Step 3: Package as Electron app
echo.
echo [3/4] Packaging Electron app...
call npm run package --workspace=packages/management
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Packaging failed. Check the output above.
    pause
    exit /b 1
)

:: Step 4: Copy entire app to project root
echo.
echo [4/4] Copying dashboard to project root...
set "SRC=packages\management\release\win-unpacked"
set "DEST=dashboard"

if not exist "%SRC%\BizarreCRM Management.exe" (
    echo ERROR: Built EXE not found at %SRC%
    pause
    exit /b 1
)

:: Clean previous build
if exist "%DEST%" rmdir /s /q "%DEST%"

:: Copy entire runtime directory
xcopy /E /I /Q /Y "%SRC%" "%DEST%" >nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to copy dashboard files.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Build complete!
echo  Run: dashboard\BizarreCRM Management.exe
echo ============================================
echo.

:: Open the dashboard folder in Explorer
explorer "%~dp0..\dashboard"
