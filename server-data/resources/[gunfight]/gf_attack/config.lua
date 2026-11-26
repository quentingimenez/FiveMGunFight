-- =============================================================================
--  gf_attack - CONFIGURATION du mode "Attaque de zone"
--
--  Principe : 2 équipes (A et B). Une équipe ATTAQUE la zone, l'autre la DÉFEND.
--  Pas de réapparition pendant une manche : la dernière équipe en vie gagne.
--  Si le temps est écoulé, c'est la DÉFENSE qui gagne.
--  Les rôles s'inversent à chaque manche. Premier à WinRounds manches = victoire.
--
--  Déroulement d'une manche :
--   1. Choix des armes (SelectTime) : les attaquants apparaissent DANS LEUR
--      VOITURE, les défenseurs À PIED dans la zone ; tout le monde est gelé
--      et choisit 2 armes parmi celles qu'il possède.
--   2. Placement (PlacementTime) : on peut rouler. Les défenseurs se placent,
--      les attaquants ne peuvent PAS encore entrer dans la zone.
--   3. Combat (RoundTime) : la zone est ouverte. Les voitures restent : on peut
--      descendre et remonter. Un joueur mort regarde ses alliés (clic gauche /
--      clic droit pour changer de joueur).
-- =============================================================================
Config = {}

-- La recherche de partie est dans gf_lobby (Config.Matchmaking) : elle fait
-- entrer les joueurs quand attackMin joueurs attendent, au plus attackMax.
-- Garder PlayersToStart = attackMin et MaxPlayers = attackMax.
-- Un admin peut lancer de force avec /startround, quel que soit le nombre.
Config.PlayersToStart = 20
Config.MaxPlayers = 30
Config.WinRounds = 2           -- manches à gagner pour remporter le match
Config.SelectTime = 10         -- secondes pour choisir ses armes (gelé dans la voiture)
Config.PlacementTime = 15      -- secondes de placement (zone fermée aux attaquants)
Config.RoundTime = 180         -- chrono de combat en secondes, en pause si un attaquant vivant est dans la zone
Config.EndDelay = 6            -- pause entre deux manches : « Manche gagnée / perdue » (secondes)
Config.MatchEndDelay = 15      -- pause après la fin d'un match (secondes)
Config.SwapSidesEveryRound = true

Config.Vehicle = 'gstbisxl3'       -- voiture des attaquants en début de manche (Bison XL Hellfire, ressource gf_vehicles)
-- Formation d'apparition (voir spawnPos dans server.lua)
Config.VehicleColumns = 3          -- voitures côte à côte par rangée
Config.VehicleSideSpacing = 3.6    -- écart (m) entre deux véhicules côte à côte (le Bison XL ≈ 2,2 m de large)
Config.VehicleRowSpacing = 7.5     -- écart (m) entre deux rangées (le Bison XL ≈ 6 m de long)
Config.FootSpacing = 1.6           -- écart (m) entre les joueurs à pied (défenseurs)

Config.AttackSpawnDistance = 70.0  -- (zones de secours) distance des attaquants au-delà du bord
Config.OutOfZoneDamage = 8         -- dégâts / seconde pour un défenseur hors de la zone (combat)

-- ---------------------------------------------------------------------------
-- Vie et soins (attaquants ET défenseurs)
-- Chaque joueur commence la manche avec 100 points de vie et 100 de kevlar
-- (gilet donné avec les armes : Config.SelectionArmour de gf_core).
-- Objets de soin, remis à chaque début de manche :
--   touche 3 : bandage  -> +50 points de vie
--   touche 4 : kevlar   -> +50 de kevlar
-- Utilisation : petite animation, on peut continuer à se déplacer mais pas
-- tirer pendant ce temps. Chaque kill sur un ennemi rapporte 1 kevlar.
-- ---------------------------------------------------------------------------
Config.StartBandages = 2
Config.StartKevlars = 2
Config.KevlarPerKill = 1
Config.MaxKevlars = 2              -- kevlars qu'on peut porter au maximum (un kill à 2 n'en rapporte pas)

Config.Items = {
    bandage = {
        label = 'Bandage', key = '3', stat = 'health', amount = 50, duration = 3.0,
        anim = { dict = 'mp_arresting', name = 'a_uncuff' },
    },
    kevlar = {
        label = 'Kevlar', key = '4', stat = 'armour', amount = 50, duration = 3.5,
        anim = { dict = 'clothingtie', name = 'try_tie_negative_a' },
    },
}

-- Opacité du remplissage rouge de la zone sur la carte (0 à 255).
-- 255 = rouge plein ; plus bas = on voit les rues à travers, mais les cercles
-- qui composent le remplissage se devinent un peu là où ils se chevauchent.
Config.MapFillAlpha = 210

Config.Teams = {
    A = { label = 'Équipe Rouge', color = '#ff5a5f' },
    B = { label = 'Équipe Bleue', color = '#4ea8ff' },
}

-- Les zones se créent EN JEU avec /editor (admin) : contour point par point,
-- départ des attaquants et des défenseurs. Les zones ci-dessous ne servent que
-- de SECOURS tant qu'aucune zone d'attaque n'a été créée avec l'éditeur.
-- Les joueurs inscrits dans la file du lobby votent pour la carte du prochain
-- match ; sans vote, les cartes sont jouées à tour de rôle. Les zones de secours
-- n'ont pas d'id et sont votées sous secours_N (N = rang dans la liste).
--   center     : centre de la zone (la hauteur z est corrigée automatiquement)
--   radius      : rayon en mètres
--   attackFrom  : direction d'où arrivent les attaquants, en degrés
--                 (0 = nord, 90 = est, 180 = sud, 270 = ouest)
-- Astuce : en jeu, tape /pos pour afficher tes coordonnées actuelles.
Config.Zones = {
    { name = 'Legion Square',          center = vector3(195.2, -933.8, 30.7),  radius = 60.0, attackFrom = 0 },
    { name = 'Grove Street',           center = vector3(105.0, -1940.0, 20.8), radius = 55.0, attackFrom = 90 },
    { name = 'Aérodrome Sandy Shores', center = vector3(1730.0, 3290.0, 41.1), radius = 80.0, attackFrom = 270 },
}
