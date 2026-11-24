@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Console du serveur : tape une commande puis Entree (ex : restart gf_attack, status)
echo Pour quitter SANS arreter le serveur : Ctrl+P puis Ctrl+Q
echo.
docker attach gunfight-fxserver
