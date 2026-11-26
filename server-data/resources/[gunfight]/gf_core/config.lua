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

-- Garde des state bags : intervalle minimal entre deux signalements d'anomalie
-- pour un même joueur et une même clé (millisecondes). Valeur choisie, non
-- mesurée : elle limite seulement le volume du journal ; le rétablissement de
-- la valeur serveur reste immédiat à chaque écriture.
Config.StateGuard = { reportIntervalMs = 5000 }

-- Créditation des kills : fenêtre (secondes) pendant laquelle le dernier dégât
-- autorisé vu par weaponDamageEvent désigne le tueur. Au-delà, aucun kill
-- n'est crédité (le client ne peut pas fournir lui-même un tueur).
Config.KillCreditWindow = 10

-- Vérifie côté serveur que la victime est bien morte (santé <= 0) avant de
-- traiter une mort. Passe à false si des morts légitimes sont rejetées sur ton
-- serveur (voir docs/evenements-serveur.md).
Config.ValidateDeathHealth = true

-- La mort n'est signalée qu'UNE fois par le client (baseevents), parfois avant
-- que la santé à 0 soit arrivée au serveur (mort écrasé par un véhicule). La
-- vérification est alors refaite toutes les delayMs, au plus tries fois. Après
-- le dernier essai, la mort est traitée sans kill crédité : sinon le joueur ne
-- réapparaîtrait jamais.
Config.DeathConfirm = { tries = 8, delayMs = 250 }

-- Multi-kills : délai max (secondes) entre deux kills pour enchaîner
-- DOUBLÉ, TRIPLÉ, QUADRUPLÉ, QUINTUPLÉ... (remis à zéro si tu meurs)
Config.MultiKillWindow = 6

-- Collisions entre véhicules désactivées (pas de « pit » entre joueurs)
Config.DisableVehicleCollisions = true

-- Régénération naturelle de la vie (false = pas de régénération, plus "gunfight")
Config.HealthRegen = false

-- ---------------------------------------------------------------------------
-- Armes au choix (Attaque de zone : chaque joueur choisit 2 armes avant la manche)
--
-- Catalogue de toutes les armes connues du serveur. Plus tard, le système de
-- caisses ajoutera des armes customisées (components = accessoires, tint =
-- couleur) que chaque joueur pourra gagner. Pour l'instant, tout le monde
-- possède les armes de Config.StarterWeapons.
--   name       : nom GTA de l'arme
--   label      : nom affiché dans le menu
--   category   : catégorie affichée dans le menu
--   ammo       : munitions données
--   components : (optionnel) accessoires GTA, ex. { 'COMPONENT_AT_SCOPE_MEDIUM' }
--   tint       : (optionnel) couleur de l'arme (0 à 7)
-- ---------------------------------------------------------------------------
Config.Weapons = {
    carbine     = { name = 'WEAPON_CARBINERIFLE',   label = 'Carabine',            category = 'Fusil d\'assaut', ammo = 300 },
    assault     = { name = 'WEAPON_ASSAULTRIFLE',   label = 'Fusil d\'assaut',     category = 'Fusil d\'assaut', ammo = 300 },
    special     = { name = 'WEAPON_SPECIALCARBINE', label = 'Carabine spéciale',   category = 'Fusil d\'assaut', ammo = 300 },
    bullpup     = { name = 'WEAPON_BULLPUPRIFLE',   label = 'Fusil bullpup',       category = 'Fusil d\'assaut', ammo = 300 },
    smg         = { name = 'WEAPON_SMG',            label = 'SMG',                 category = 'Mitraillette',    ammo = 360 },
    pdw         = { name = 'WEAPON_COMBATPDW',      label = 'PDW',                 category = 'Mitraillette',    ammo = 360 },
    pump        = { name = 'WEAPON_PUMPSHOTGUN',    label = 'Fusil à pompe',       category = 'Fusil à pompe',   ammo = 60 },
    marksman    = { name = 'WEAPON_MARKSMANRIFLE',  label = 'Fusil de précision',  category = 'Précision',       ammo = 60 },
    pistol      = { name = 'WEAPON_PISTOL',         label = 'Pistolet',            category = 'Pistolet',        ammo = 96 },
    pistol50    = { name = 'WEAPON_PISTOL50',       label = 'Pistolet .50',        category = 'Pistolet',        ammo = 72 },
    heavypistol = { name = 'WEAPON_HEAVYPISTOL',    label = 'Pistolet lourd',      category = 'Pistolet',        ammo = 72 },
}

-- Armes que tout le monde possède dès le départ (identifiants de Config.Weapons)
Config.StarterWeapons = { 'carbine', 'assault', 'special', 'bullpup', 'smg', 'pdw', 'pump', 'marksman', 'pistol', 'pistol50', 'heavypistol' }

-- Choix par défaut si le joueur ne choisit rien
Config.DefaultSelection = { 'carbine', 'pistol' }

-- Nombre d'armes à choisir et gilet pare-balles donné avec
Config.SelectionCount = 2

-- Changement d'arme : la roue de GTA est désactivée. Les touches 1, 2...
-- sortent l'arme choisie en 1re, 2e... position (modifiable par chaque joueur
-- dans Paramètres > Raccourcis clavier > FiveM).
Config.WeaponSlots = 2
Config.SelectionArmour = 100

-- Équipements fixes (Redzone). armour = gilet pare-balles (0 à 100). Noms des armes :
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

-- ---------------------------------------------------------------------------
-- Validation des tirs (côté serveur, module pur shot_validation.lua)
-- enabled : active la vérification des dégâts reçus par weaponDamageEvent.
-- alwaysAllowed : armes toujours autorisées, même hors loadout (poings).
-- forbidden : dégâts toujours refusés entre joueurs, loadout ou non :
--   explosions (arme donnée par un tricheur, véhicule qui saute) et chocs de
--   véhicule (écrasement, percussion). Les explosions elles-mêmes sont aussi
--   annulées par explosionEvent.
-- damageCaps : par nom d'arme, plafonds de dégâts { body = n, head = n }.
--   LAISSE VIDE tant que le chantier C6 n'a pas extrait les valeurs de
--   weapons.meta : ne jamais inventer de chiffre.
-- fireIntervals : par nom d'arme, millisecondes entre deux tirs.
--   LAISSE VIDE tant que le chantier C6 n'a pas extrait les valeurs de
--   weapons.meta : ne jamais inventer de chiffre.
-- headComponents : composants GTA comptés comme « tête ». À confirmer en jeu.
-- networkToleranceMs : tolérance sur l'horodatage réseau des tirs.
-- ---------------------------------------------------------------------------
Config.ShotValidation = {
    enabled = true,
    alwaysAllowed = { 'WEAPON_UNARMED' },
    forbidden = { 'WEAPON_EXPLOSION', 'WEAPON_RUN_OVER_BY_CAR', 'WEAPON_RAMMED_BY_CAR' },
    damageCaps = {},
    fireIntervals = {},
    headComponents = { 20 },
    networkToleranceMs = 50,
}
