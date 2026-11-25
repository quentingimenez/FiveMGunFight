fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_lobby'
description 'Lobby statique Gunfight : personnage, escouade et selection de mode'
author 'Gunfight'
version '1.0.0'

shared_script 'config.lua'

client_scripts {
  'appearance.lua',
  'client.lua',
}

server_script 'server.lua'

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/css/base.css',
  'html/css/modes.css',
  'html/css/squad.css',
  'html/css/creator.css',
  'html/css/customization.css',
  'html/js/nui.js',
  'html/js/app.js',
  'html/js/modes.js',
  'html/js/squad.js',
  'html/js/creator.js',
  'html/js/customization.js',
}

dependencies {
  'gf_core',
}
