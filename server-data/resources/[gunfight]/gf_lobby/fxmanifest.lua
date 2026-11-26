fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_lobby'
description 'Lobby statique Gunfight : personnage, escouade et selection de mode'
author 'Gunfight'
version '1.1.0'

shared_script 'config.lua'
shared_script 'appearance_schema.lua'

client_scripts {
  'appearance.lua',
  'backdrop.lua',
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
  'html/data/tattoos.json',
  -- Image du fond de scène, chargée par CreateRuntimeTextureFromImage (client.lua).
  'img/backdrop.jpg',
}

dependencies {
  'gf_core',
}
