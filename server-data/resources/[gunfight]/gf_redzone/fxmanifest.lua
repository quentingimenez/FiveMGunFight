fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_redzone'
description 'Gunfight : Redzone (zones de combat libres, réapparition rapide, classement)'
version '1.0.0'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'

dependencies {
    'gf_core',
    'gf_ui',
    'gf_maps',
}
