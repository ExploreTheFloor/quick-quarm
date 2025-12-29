@echo off
echo Stopping Quick Quarm Server...
wsl -d Ubuntu-22.04 sudo systemctl stop quick-quarm.target
echo Server stop command sent.
pause

