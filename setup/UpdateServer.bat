@echo off
echo Updating Quick Quarm Server...
echo This will stop the server, update code and database, then restart the server.
echo.
wsl -d Ubuntu-22.04 bash -c "cd /root/quick-quarm && sudo ./scripts/update"
echo.
echo Update complete!
pause

