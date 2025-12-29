@echo off
echo Checking Quick Quarm Server Status...
wsl -d Ubuntu-22.04 sudo systemctl status quick-quarm.target
pause

