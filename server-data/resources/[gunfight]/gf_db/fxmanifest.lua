fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_db'
author 'FiveMGunFight'
description 'Migrations de schéma MariaDB appliquées au démarrage via oxmysql.'
version '1.0.0'

dependency 'oxmysql'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'plan.lua',
    'migrations.lua',
    'server.lua',
}

files {
    'migrations/0001_gf_stats_players.sql',
    'migrations/0002_gf_match_events.sql',
    'migrations/0003_gf_player_weapons.sql',
}
