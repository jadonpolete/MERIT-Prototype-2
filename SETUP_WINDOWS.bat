@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Install Node.js 20 or newer, reopen this folder, and run this file again.
  pause
  exit /b 1
)
where npm >nul 2>nul
if errorlevel 1 (
  echo npm was not found. Reinstall Node.js with npm included.
  pause
  exit /b 1
)
echo Installing the pinned local-demo dependencies. Internet is needed once.
call npm ci --no-audit --no-fund
if errorlevel 1 (
  echo Setup failed. Check the message above.
  pause
  exit /b 1
)
echo Setup complete. Run START_WINDOWS.bat next.
pause
