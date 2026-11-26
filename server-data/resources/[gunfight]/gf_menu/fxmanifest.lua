fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_menu'
description 'Gunfight : menu pause personnalisé (remplace le menu pause de GTA V)'
version '1.0.0'

ui_page 'html/index.html'

shared_script 'config.lua'
shared_script 'menu_state.lua'
server_script 'server.lua'
client_script 'client.lua'

dependencies {
    'gf_core',
    'gf_stats',
}

files {
    'html/index.html',
    'html/css/menu.css',
    'html/js/nui.js',
    'html/js/nav.js',
    'html/js/app.js',
}
