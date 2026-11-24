@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Serveur Gunfight

where docker >nul 2>nul
if errorlevel 1 (
  echo [ERREUR] Docker n'est pas installe. Installe Docker Desktop : https://www.docker.com/products/docker-desktop/
  pause
  exit /b 1
)

docker info >nul 2>nul
if errorlevel 1 (
  echo [ERREUR] Docker Desktop n'est pas demarre. Lance-le, attends qu'il soit pret, puis relance ce fichier.
  pause
  exit /b 1
)

if not exist ".env" (
  copy ".env.example" ".env" >nul
  echo Le fichier .env vient d'etre cree. Remplis au minimum LICENSE_KEY, enregistre, puis relance start.bat.
  notepad ".env"
  exit /b 0
)

findstr /c:"LICENSE_KEY=change_moi" ".env" >nul 2>nul
if not errorlevel 1 (
  echo.
  echo [ERREUR] La cle de licence n'est pas renseignee dans .env
  echo          Cree ta cle sur https://portal.cfx.re puis colle-la apres LICENSE_KEY=
  echo          Tu peux aussi verifier les autres valeurs avec la commande :
  echo          type .env
  echo.
  notepad ".env"
  pause
  exit /b 1
)

echo Construction et demarrage du serveur (la premiere fois peut prendre quelques minutes)...
docker compose up -d --build
if errorlevel 1 (
  echo [ERREUR] Le demarrage a echoue. Lis les messages ci-dessus.
  pause
  exit /b 1
)

echo.
echo === Demarre ===
echo Serveur      : dans FiveM, touche F8 puis tape  connect localhost
echo Panneau web  : http://localhost:40120  (code PIN affiche dans les journaux ci-dessous)
echo Journaux     : ferme cette fenetre quand tu veux, le serveur continue de tourner
echo Etat du serveur a tout moment : double-clic sur status.bat
echo.
docker compose logs -f --tail 100 fxserver
