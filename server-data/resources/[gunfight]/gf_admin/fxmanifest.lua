fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_admin'
description "Gunfight : panneau d'administration"
version '1.0.0'

ui_page 'html/index.html'

shared_script 'commands.lua'
server_script 'server.lua'
client_script 'client.lua'

dependencies {
    'gf_core',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
