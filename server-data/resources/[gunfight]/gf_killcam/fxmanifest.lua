fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_killcam'
description "Gunfight : killcam, la victime revoit les dernières secondes du point de vue de son tueur"
version '1.0.0'

shared_scripts {
    'config.lua',
    'track.lua',
}

client_scripts {
    'record.lua',
    'replay.lua',
}

server_script 'server.lua'

dependency 'gf_core'
