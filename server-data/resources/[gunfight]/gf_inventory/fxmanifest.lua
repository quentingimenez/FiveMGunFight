fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_inventory'
description 'Armes possédées et équipées des joueurs'
version '1.0.0'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'accessories.lua',
    'server.lua',
}

dependencies { 'oxmysql', 'gf_db', 'gf_core', 'gf_weapons' }
