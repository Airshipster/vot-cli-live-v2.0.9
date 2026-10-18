@echo off
set "VOT_PWSH="
if not defined VOT_PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "VOT_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
for /f "delims=" %%P in ('where pwsh.exe 2^>nul') do if not defined VOT_PWSH set "VOT_PWSH=%%P"
if not defined VOT_PWSH (
  echo Install PowerShell 7: winget install --id Microsoft.PowerShell -e
  pause
  exit /b 1
)
"%VOT_PWSH%" -NoLogo -NoProfile -STA -NoExit -File "%~dp0Run-VOT.ps1" %*
