fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_audit'
author 'FiveMGunFight'
description 'Audit passif côté serveur de la vie et de l\'armure : journalise les anomalies, sans sanction.'
version '1.0.0'

dependency 'gf_core'

server_scripts {
    '@gf_core/validation.lua',
    'audit.lua',
    'config.lua',
    'server.lua',
}
