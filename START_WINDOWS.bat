@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Install Node.js 20 or newer first.
  pause
  exit /b 1
)
if not exist node_modules\ethers\package.json (
  echo Run SETUP_WINDOWS.bat first.
  pause
  exit /b 1
)
node server.cjs
pause
