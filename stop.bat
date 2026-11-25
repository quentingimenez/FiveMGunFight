@echo off
chcp 65001 >nul
cd /d "%~dp0"
rem Même combinaison de fichiers que start.bat (socle + développement)
set COMPOSE_FILE=docker-compose.yml;docker-compose.dev.yml
echo Arret du serveur...
docker compose down
echo Serveur arrete.
pause
