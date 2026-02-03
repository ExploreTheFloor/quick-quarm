@echo off
REM Quick Quarm - Hyper-V VM Management Console
REM Menu wrapper for Hyper-V scripts in this folder.

REM Optional self-elevation so output/progress stays in one window.
REM (Fix/Undo/Installer/Uninstaller typically require admin anyway.)
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo ========================================
  echo NOTE: Not running as Administrator
  echo ========================================
  echo Some options ^(Fix/Undo/Installer/Uninstaller^) require elevation.
  echo Relaunch this console as Administrator for best experience.
  echo.
  set /p elevate="Relaunch as Administrator now? (Y/N): "
  if /i "%elevate%"=="Y" (
    powershell -NoProfile -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
  )
)

:MENU
cls
echo ========================================
echo Quick Quarm Hyper-V Management Console
echo ========================================
echo.
echo VM OPERATIONS:
echo   1. Start VM
echo   2. Stop VM
echo   3. Restart VM
echo   4. VM/Server Status
echo   5. Connect to VM (SSH)
echo   6. View Server Logs
echo.
echo CONNECTION TOOLS:
echo   7. Diagnose Connection Issues
echo   8. Fix Connection (Requires Admin)
echo   9. Undo Connection Fix (Requires Admin)
echo.
echo ADVANCED (Use with Caution):
echo   I. Run Hyper-V Installer (Creates/Recreates VM)
echo   U. Uninstall Hyper-V VM (Deletes VM + files)
echo.
echo   0. Exit
echo.
set /p choice="Select option (0-9, I, U): "

if "%choice%"=="1" goto START
if "%choice%"=="2" goto STOP
if "%choice%"=="3" goto RESTART
if "%choice%"=="4" goto STATUS
if "%choice%"=="5" goto SSH
if "%choice%"=="6" goto LOGS
if "%choice%"=="7" goto DIAGNOSE
if "%choice%"=="8" goto FIX_CONNECTION
if "%choice%"=="9" goto UNDO_CONNECTION
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
echo Starting Quick Quarm Hyper-V VM
echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action Start
echo.
pause
goto MENU

:STOP
cls
echo ========================================
echo Stopping Quick Quarm Hyper-V VM
echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action Stop
echo.
pause
goto MENU

:RESTART
cls
echo ========================================
echo Restarting Quick Quarm Hyper-V VM
echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action Restart
echo.
pause
goto MENU

:STATUS
cls
echo ========================================
echo Quick Quarm Hyper-V VM / Server Status
echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action Status
echo.
pause
goto MENU

:SSH
cls
echo ========================================
echo Connect to VM (SSH)
echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action SSH
echo.
pause
goto MENU

:LOGS
cls
echo ========================================
echo Quick Quarm Server Logs
echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action Logs
echo.
pause
goto MENU

:DIAGNOSE
cls
echo ========================================
echo Connection Diagnostics (Hyper-V)
echo ========================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action Diagnose
echo.
pause
goto MENU

:FIX_CONNECTION
cls
echo ========================================
echo Fix Connection (Hyper-V)
echo ========================================
echo.
echo NOTE: This requires Administrator privileges.
echo.
net session >nul 2>&1
if %errorlevel% equ 0 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action FixConnection
) else (
  REM Run in an elevated PowerShell window and keep it open so output is visible.
  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File','%~dp0QuarmFixer-HyperV.ps1','-Action','FixConnection')"
)
echo.
pause
goto MENU

:UNDO_CONNECTION
cls
echo ========================================
echo Undo Connection Fix (Hyper-V)
echo ========================================
echo.
echo NOTE: This requires Administrator privileges.
echo.
net session >nul 2>&1
if %errorlevel% equ 0 (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmFixer-HyperV.ps1" -Action UndoConnection
) else (
  REM Run in an elevated PowerShell window and keep it open so output is visible.
  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File','%~dp0QuarmFixer-HyperV.ps1','-Action','UndoConnection')"
)
echo.
pause
goto MENU

:INSTALLER
cls
echo ========================================
echo Quick Quarm Hyper-V Installer
echo ========================================
echo.
echo WARNING: This will install/reinstall Quick Quarm on a Hyper-V VM.
echo This may overwrite existing VM/configurations!
echo.
set /p confirm="Are you sure you want to continue? (yes/no): "
if /i "%confirm%"=="yes" (
    echo.
    echo Launching installer with Administrator privileges...
    echo You may see a UAC prompt - please click Yes.
    echo.
    net session >nul 2>&1
    if %errorlevel% equ 0 (
      powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmInstaller-HyperV.ps1"
    ) else (
      powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File','%~dp0QuarmInstaller-HyperV.ps1')"
    )
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
echo Quick Quarm Hyper-V Uninstaller
echo ========================================
echo.
echo WARNING: This will COMPLETELY REMOVE the Hyper-V VM!
echo The VM and all data inside it will be deleted!
echo.
set /p confirm="Type UNINSTALL to confirm: "
if /i %confirm%==UNINSTALL (
    echo.
    echo Launching uninstaller with Administrator privileges...
    echo You may see a UAC prompt - please click Yes.
    echo.
    net session >nul 2>&1
    if %errorlevel% equ 0 (
      powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuarmUninstaller-HyperV.ps1"
    ) else (
      powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File','%~dp0QuarmUninstaller-HyperV.ps1')"
    )
    echo.
    pause
) else (
    echo.
    echo Uninstall cancelled - confirmation text did not match.
    echo.
    pause
)
goto MENU

:EXIT
exit

