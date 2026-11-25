fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_maps'
description 'Gunfight : éditeur de maps en jeu (redzones et zones d\'attaque) + stockage'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

server_script 'server.lua'
client_script 'client.lua'

dependencies {
    'gf_core',
}
