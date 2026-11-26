fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_thumbs'
description 'Gunfight : photos (miniatures) générées en jeu à partir des modèles 3D (/thumbs), pour tous les menus'
version '1.0.0'

-- Page invisible qui capture l'image du jeu (studio photo)
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/capture.js',
}

shared_script 'config.lua'
server_scripts {
    'base64.lua',
    'server.lua',
}
client_script 'client.lua'
