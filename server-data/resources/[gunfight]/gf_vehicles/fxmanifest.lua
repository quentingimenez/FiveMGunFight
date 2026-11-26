fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_vehicles'
description 'Gunfight : véhicules ajoutés (Dodge Ram TRX = véhicule de base) et custom admin (/customveh)'
version '1.1.0'

-- Modèles 3D : tout le dossier stream/ est envoyé aux joueurs automatiquement.
-- Dodge Ram TRX 2021 (modèle libre « HarvinoiiDRamTRX ») : nom de modèle « theramtrx21 ».
ui_page 'html/index.html'

files {
    'data/vehicles.meta',
    'data/handling.meta',
    'data/carvariations.meta',
    'data/carcols.meta',
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'CARCOLS_FILE' 'data/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'
