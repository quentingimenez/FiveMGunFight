fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_screen'
description "Gunfight : visionnage discret de l'écran d'un joueur par un administrateur"
version '1.0.0'

ui_page 'html/index.html'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

dependencies { 'gf_core', 'gf_admin' }

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/vendor/three.min.js',
}
