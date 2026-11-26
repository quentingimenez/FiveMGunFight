fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_core'
description 'Gunfight : base commune (modes, spawn, armes, morts, anti friendly-fire)'
version '1.0.0'

shared_script 'config.lua'
server_script 'validation.lua'
server_script 'rate_limit.lua'
server_script 'shot_validation.lua'
server_script 'server.lua'
client_script 'client.lua'

dependencies {
    'baseevents',
    'gf_ui',
}
