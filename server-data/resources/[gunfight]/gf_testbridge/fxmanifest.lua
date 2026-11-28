fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_testbridge'
description 'passerelle de test NUI, développement uniquement'
version '1.0.0'

server_scripts {
    'guard.lua',
    'protocol.lua',
    'server.lua',
}

client_scripts {
    'protocol.lua',
    'client.lua',
}

dependencies {
    'gf_ui',
}
