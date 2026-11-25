-- =============================================================================
--  gf_core - CONFIGURATION
--  Tu peux modifier ce fichier sans risque, puis taper "restart gf_core"
--  dans la console du serveur (ou redémarrer le serveur).
-- =============================================================================
Config = {}

-- Apparence des joueurs (personnage masculin multijoueur)
Config.PlayerModel = 'mp_m_freemode_01'

-- Permission des administrateurs (voir server.cfg et ADMIN_IDENTIFIERS dans .env)
Config.AdminAce = 'gunfight.admin'

-- Point d'apparition du lobby (aéroport de Los Santos)
Config.Lobby = { x = -1037.7, y = -2737.9, z = 20.2, heading = 330.0 }

-- Chaque mode de jeu est isolé dans son propre "monde" (routing bucket) :
-- les joueurs du lobby ne voient pas ceux de la redzone, etc.
-- resource = nom de la ressource qui gère ce mode
Config.Modes = {
    lobby   = { bucket = 0, label = 'Lobby' },
    attack  = { bucket = 1, label = 'Attaque de zone', resource = 'gf_attack' },
    redzone = { bucket = 2, label = 'Redzone',         resource = 'gf_redzone' },
}

-- Distance max (mètres) entre tueur et victime pour qu'un kill soit accepté
-- (protection simple contre les faux kills envoyés par un tricheur)
Config.MaxKillDistance = 600.0

-- Multi-kills : délai max (secondes) entre deux kills pour enchaîner
-- DOUBLÉ, TRIPLÉ, QUADRUPLÉ, QUINTUPLÉ... (remis à zéro si tu meurs)
Config.MultiKillWindow = 6

-- Régénération naturelle de la vie (false = pas de régénération, plus "gunfight")
Config.HealthRegen = false

-- Équipements. armour = gilet pare-balles (0 à 100). Noms des armes :
-- https://wiki.rage.mp/index.php?title=Weapons (colonne "Name")
Config.Loadouts = {
    attack = {
        armour = 100,
        weapons = {
            { 'WEAPON_CARBINERIFLE', 300 },
            { 'WEAPON_PISTOL', 72 },
        },
    },
    redzone = {
        armour = 100,
        weapons = {
            { 'WEAPON_SPECIALCARBINE', 400 },
            { 'WEAPON_PISTOL50', 72 },
        },
    },
}
