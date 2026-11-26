fx_version 'cerulean'
game 'gta5'

name 'gf_stats'
author 'FiveMGunFight'
description 'Statistiques persistantes des joueurs (kills, morts, parties, victoires) via MariaDB/oxmysql.'
version '1.0.0'

dependency 'oxmysql'
dependency 'gf_db'

server_script 'server.lua'
