fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gf_weapons'
description 'Gunfight : armes ajoutées (modèles stream/, réglages data/<ARME>/*.meta), ajoutées par scripts/ajouter_arme.py'
version '1.0.0'

-- Modèles 3D : tout le dossier stream/ est envoyé aux joueurs automatiquement.
-- Réglages : data/<ARME>/*.meta (un dossier par arme, accessoires dans components/).
-- Le catalogue des armes (nom, catégorie, munitions) reste Config.Weapons de gf_core.
files {
    'data/index.json',
    'data/WEAPON_GHOSTFAIR/components/COMPONENT_AT_GHOSTFAIR_SUPP/weaponcomponents.meta',
    'data/WEAPON_GHOSTFAIR/components/COMPONENT_AT_SCOPE_GHOSTFAIR/weaponcomponents.meta',
    'data/WEAPON_GHOSTFAIR/components/COMPONENT_GHOSTFAIR_CLIP_01/weaponcomponents.meta',
    'data/WEAPON_GHOSTFAIR/names.json',
    'data/WEAPON_GHOSTFAIR/pedpersonality.meta',
    'data/WEAPON_GHOSTFAIR/weaponanimations.meta',
    'data/WEAPON_GHOSTFAIR/weaponarchetypes.meta',
    'data/WEAPON_GHOSTFAIR/weapons.meta',
}

data_file 'WEAPONCOMPONENTSINFO_FILE' 'data/**/weaponcomponents.meta'
data_file 'WEAPON_METADATA_FILE' 'data/**/weaponarchetypes.meta'
data_file 'WEAPON_ANIMATIONS_FILE' 'data/**/weaponanimations.meta'
data_file 'PED_PERSONALITY_FILE' 'data/**/pedpersonality.meta'
data_file 'WEAPONINFO_FILE' 'data/**/weapons.meta'

client_script 'client.lua'
