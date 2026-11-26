fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_vehicles'
description 'Gunfight : véhicules du serveur (Bison XL Hellfire, Jeep Trackhawk), véhicule de base et custom admin (/customveh)'
version '1.3.0'

-- Modèles 3D et pièces : tout le dossier stream/ est envoyé aux joueurs automatiquement.
-- Réglages : data/<modèle>/*.meta (un dossier par véhicule, listé dans Config.Vehicles).
--  - Bravado Bison XL Hellfire (pack « cfx-gomstyling-gstbisxl3 ») : « gstbisxl3 »,
--    pièces de carrosserie gstbisxl2_*.yft, son moteur « lg247hemi57 ».
--  - Jeep Trackhawk (pack « keyhawk ») : « keyhawk », utilise le son du Bison.
ui_page 'html/index.html'

files {
    'data/gstbisxl3/vehicles.meta',
    'data/gstbisxl3/handling.meta',
    'data/gstbisxl3/carvariations.meta',
    'data/gstbisxl3/carcols.meta',
    'data/keyhawk/vehicles.meta',
    'data/keyhawk/handling.meta',
    'data/keyhawk/carvariations.meta',
    'audioconfig/lg247hemi57_game.dat151.rel',
    'audioconfig/lg247hemi57_sounds.dat54.rel',
    'sfx/dlc_lg247hemi57/lg247hemi57.awc',
    'sfx/dlc_lg247hemi57/lg247hemi57_npc.awc',
    'data/gbbisonhf/carcols.meta',
    'data/gbbisonhf/carvariations.meta',
    'data/gbbisonhf/handling.meta',
    'data/gbbisonhf/vehicles.meta',
    'data/gbbisonhf/names.json',
    'data/astronmans/carcols.meta',
    'data/astronmans/carvariations.meta',
    'data/astronmans/handling.meta',
    'data/astronmans/vehicles.meta',
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

data_file 'HANDLING_FILE' 'data/**/handling.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/**/vehicles.meta'
data_file 'CARCOLS_FILE' 'data/**/carcols.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/**/carvariations.meta'
data_file 'AUDIO_GAMEDATA' 'audioconfig/lg247hemi57_game.dat'
data_file 'AUDIO_SOUNDDATA' 'audioconfig/lg247hemi57_sounds.dat'
data_file 'AUDIO_WAVEPACK' 'sfx/dlc_lg247hemi57'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'
