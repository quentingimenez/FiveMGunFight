fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_journal'
author 'FiveMGunFight'
description 'Journal des événements de match, écrit par lots dans MariaDB via oxmysql.'
version '1.0.0'

dependencies {
    'oxmysql',
    'gf_db',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'journal.lua',
    'server.lua',
}
