@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Arret du serveur...
docker compose down
echo Serveur arrete.
pause
