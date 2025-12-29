@echo off
REM Quick Quarm Installation Verification
REM This batch file runs the verification script

echo ========================================
echo Quick Quarm Installation Verification
echo ========================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0Verify-QuarmInstall.ps1"

echo.
pause

