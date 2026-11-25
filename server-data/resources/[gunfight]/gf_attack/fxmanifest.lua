fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_attack'
description 'Gunfight : Attaque de zone (2 équipes, attaque / défense, dernière équipe en vie)'
version '1.0.0'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'

dependencies {
    'gf_core',
    'gf_ui',
    'gf_maps',
}
