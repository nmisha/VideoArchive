@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VideoArchive.ps1"
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "[Console]::InputEncoding=[System.Text.UTF8Encoding]::new($false); [Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false); $OutputEncoding=[System.Text.UTF8Encoding]::new($false); & '%~dp0VideoArchive.ps1'"
)
pause
