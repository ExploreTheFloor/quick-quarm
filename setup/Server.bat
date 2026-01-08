@echo off
REM Quick Quarm - All-in-One Server Management
REM This script provides a unified interface for all Quick Quarm management tasks

:MENU
cls
echo ========================================
echo Quick Quarm Management Console
echo ========================================
echo.
echo SERVER OPERATIONS:
echo   1. Start Server
echo   2. Stop Server
echo   3. Check Server Status
echo.
echo CONNECTION TOOLS:
echo   4. Diagnose Connection Issues
echo   5. Fix Connection (Requires Admin)
echo   6. Undo Connection Fix (Requires Admin)
echo.
echo MAINTENANCE:
echo   7. Update Server
echo   8. Update Client Config (eqhost.txt)
echo   9. Verify Installation
echo.
echo ADVANCED (Use with Caution):
echo   I. Run Installer (Overwrites existing setup)
echo   U. Uninstall Quick Quarm
echo.
echo   0. Exit
echo.
set /p choice="Select option (0-9, I, U): "

if "%choice%"=="1" goto START
if "%choice%"=="2" goto STOP
if "%choice%"=="3" goto STATUS
if "%choice%"=="4" goto DIAGNOSE
if "%choice%"=="5" goto FIX_CONNECTION
if "%choice%"=="6" goto UNDO_CONNECTION
if "%choice%"=="7" goto UPDATE_SERVER
if "%choice%"=="8" goto UPDATE_CLIENT
if "%choice%"=="9" goto VERIFY
if /i "%choice%"=="I" goto INSTALLER
if /i "%choice%"=="U" goto UNINSTALLER
if "%choice%"=="0" goto EXIT
echo.
echo Invalid option. Please try again.
echo.
pause
goto MENU

:START
cls
echo ========================================
echo Starting Quick Quarm Server
echo ========================================
echo.
wsl -d Ubuntu-22.04 sudo systemctl start quick-quarm.target
echo.
echo Server start command sent.
echo.
pause
goto MENU

:STOP
cls
echo ========================================
echo Stopping Quick Quarm Server
echo ========================================
echo.
wsl -d Ubuntu-22.04 sudo systemctl stop quick-quarm.target
echo.
echo Server stop command sent.
echo.
pause
goto MENU

:STATUS
cls
echo ========================================
echo Quick Quarm Server Status
echo ========================================
echo.
wsl -d Ubuntu-22.04 sudo systemctl status quick-quarm.target
echo.
pause
goto MENU

:DIAGNOSE
cls
echo ========================================
echo Connection Diagnostics
echo ========================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Connection.ps1" -Action Diagnose
echo.
pause
goto MENU

:FIX_CONNECTION
cls
echo ========================================
echo Fix Connection
echo ========================================
echo.
echo NOTE: This requires Administrator privileges
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Connection.ps1" -Action Fix
echo.
pause
goto MENU

:UNDO_CONNECTION
cls
echo ========================================
echo Undo Connection Fix
echo ========================================
echo.
echo NOTE: This requires Administrator privileges
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Connection.ps1" -Action Undo
echo.
pause
goto MENU

:UPDATE_SERVER
cls
echo ========================================
echo Update Server
echo ========================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Update-Server.ps1"
echo.
pause
goto MENU

:UPDATE_CLIENT
cls
echo ========================================
echo Update Client Configuration
echo ========================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Update-EQHost.ps1"
echo.
pause
goto MENU

:VERIFY
cls
echo ========================================
echo Verify Installation
echo ========================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0Verify-QuarmInstall.ps1"
echo.
pause
goto MENU

:INSTALLER
cls
echo ========================================
echo Quick Quarm Installer
echo ========================================
echo.
echo WARNING: This will install/reinstall Quick Quarm.
echo This may overwrite existing configurations!
echo.
set /p confirm="Are you sure you want to continue? (yes/no): "
if /i "%confirm%"=="yes" (
    echo.
    echo Launching installer with Administrator privileges...
    echo You may see a UAC prompt - please click Yes.
    echo.
    powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0QuarmInstaller.ps1\"' -Verb RunAs -Wait"
    echo.
    pause
) else (
    echo.
    echo Installation cancelled.
    echo.
    pause
)
goto MENU

:UNINSTALLER
cls
echo ========================================
echo Quick Quarm Uninstaller
echo ========================================
echo.
echo WARNING: This will COMPLETELY REMOVE Quick Quarm!
echo All data and configurations will be deleted!
echo.
set /p confirm="Are you sure you want to UNINSTALL? (yes/no): "
if /i "%confirm%"=="yes" (
    echo.
    set /p doublecheck="Type UNINSTALL to confirm: "
    if /i "%doublecheck%"=="UNINSTALL" (
        echo.
        echo Launching uninstaller with Administrator privileges...
        echo You may see a UAC prompt - please click Yes.
        echo.
        powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%~dp0QuarmUninstaller.ps1\"' -Verb RunAs -Wait"
        echo.
        pause
    ) else (
        echo.
        echo Uninstall cancelled - confirmation text did not match.
        echo.
        pause
    )
) else (
    echo.
    echo Uninstall cancelled.
    echo.
    pause
)
goto MENU

:EXIT
exit
