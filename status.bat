@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Etat du serveur Gunfight

where docker >nul 2>nul
if errorlevel 1 (
  echo [ERREUR] Docker n'est pas installe. Installe Docker Desktop : https://www.docker.com/products/docker-desktop/
  pause
  exit /b 1
)

docker info >nul 2>nul
if errorlevel 1 (
  echo [ERREUR] Docker Desktop n'est pas demarre. Lance-le et attends l'icone verte.
  pause
  exit /b 1
)

echo === Conteneurs ===
docker compose ps
echo.
echo === 40 dernieres lignes du serveur ===
docker compose logs --tail 40 fxserver
echo.
pause
