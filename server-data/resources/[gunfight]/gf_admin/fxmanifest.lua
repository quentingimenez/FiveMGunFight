fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_admin'
description "Gunfight : panneau d'administration"
version '1.0.0'

ui_page 'html/index.html'

shared_script 'commands.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'audit.lua',
    'server.lua',
}
client_script 'client.lua'

dependencies { 'oxmysql', 'gf_core', 'gf_db', 'gf_ui' }

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
