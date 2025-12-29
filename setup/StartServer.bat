@echo off
echo Starting Quick Quarm Server...
wsl -d Ubuntu-22.04 sudo systemctl start quick-quarm.target
echo Server start command sent.
pause

