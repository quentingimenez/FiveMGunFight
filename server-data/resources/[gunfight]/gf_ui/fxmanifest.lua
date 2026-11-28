fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_ui'
description 'Gunfight : interface (HUD, kill feed, annonces, classement)'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

client_scripts {
    'layers.lua',
    'client.lua',
}
