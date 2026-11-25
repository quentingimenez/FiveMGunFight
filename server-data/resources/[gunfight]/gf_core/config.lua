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

-- ---------------------------------------------------------------- Sécurité
-- Véhicule de mode : le client crée le véhicule puis envoie son netId. Le
-- serveur ne le rattache au joueur que si l'entité existe, est un véhicule,
-- lui appartient sur le réseau et se trouve à moins de cette distance.
Config.VehicleBindDistance = 50.0

-- Rate-limits (fenêtre glissante, par joueur). max = nombre d'actions
-- autorisées pendant window millisecondes.
Config.VehicleRateLimit = { max = 5, window = 10000 }
Config.VehicleGoneRateLimit = { max = 5, window = 10000 }
Config.ReadyRateLimit = { max = 1, window = 5000 }

-- Journalisation des refus : au plus un message par joueur et par fenêtre,
-- pour qu'un client qui insiste ne remplisse pas la console.
Config.RefusLogRateLimit = { max = 1, window = 60000 }

-- Créditation des kills : fenêtre (secondes) pendant laquelle le dernier dégât
-- autorisé vu par weaponDamageEvent désigne le tueur. Au-delà, aucun kill
-- n'est crédité (le client ne peut pas fournir lui-même un tueur).
Config.KillCreditWindow = 10

-- Vérifie côté serveur que la victime est bien morte (santé <= 0) avant de
-- traiter une mort. Passe à false si des morts légitimes sont rejetées sur ton
-- serveur (voir docs/evenements-serveur.md).
Config.ValidateDeathHealth = true

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
