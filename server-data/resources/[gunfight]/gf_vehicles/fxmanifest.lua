fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_vehicles'
description 'Gunfight : véhicules ajoutés (Bison XL Hellfire = véhicule de base) et custom admin (/customveh)'
version '1.2.0'

-- Modèles 3D et pièces : tout le dossier stream/ est envoyé aux joueurs automatiquement.
-- Bravado Bison XL Hellfire (pack « cfx-gomstyling-gstbisxl3 ») : nom de modèle « gstbisxl3 »,
-- pièces de carrosserie gstbisxl2_*.yft, son moteur « lg247hemi57 ».
ui_page 'html/index.html'

files {
    'data/vehicles.meta',
    'data/handling.meta',
    'data/carvariations.meta',
    'data/carcols.meta',
    'audioconfig/lg247hemi57_game.dat151.rel',
    'audioconfig/lg247hemi57_sounds.dat54.rel',
    'sfx/dlc_lg247hemi57/lg247hemi57.awc',
    'sfx/dlc_lg247hemi57/lg247hemi57_npc.awc',
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'
data_file 'CARCOLS_FILE' 'data/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'
data_file 'AUDIO_GAMEDATA' 'audioconfig/lg247hemi57_game.dat'
data_file 'AUDIO_SOUNDDATA' 'audioconfig/lg247hemi57_sounds.dat'
data_file 'AUDIO_WAVEPACK' 'sfx/dlc_lg247hemi57'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'
