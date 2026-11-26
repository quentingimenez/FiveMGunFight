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
