-- =============================================================================
--  gf_attack - CONFIGURATION du mode "Attaque de zone"
--
--  Principe : 2 équipes (A et B). Une équipe ATTAQUE la zone, l'autre la DÉFEND.
--  Pas de réapparition pendant une manche : la dernière équipe en vie gagne.
--  Si le temps est écoulé, c'est la DÉFENSE qui gagne.
--  Les rôles s'inversent à chaque manche. Premier à WinRounds manches = victoire.
-- =============================================================================
Config = {}

Config.MinPlayers = 20         -- joueurs nécessaires pour lancer automatiquement (file serveur gf_lobby)
Config.WinRounds = 5           -- manches à gagner pour remporter le match
Config.PrepTime = 15           -- secondes de préparation (joueurs gelés)
Config.RoundTime = 180         -- durée max d'une manche (secondes)
Config.EndDelay = 8            -- pause entre deux manches (secondes)
Config.MatchEndDelay = 15      -- pause après la fin d'un match (secondes)
Config.SwapSidesEveryRound = true

Config.AttackSpawnDistance = 70.0  -- distance (m) des attaquants AU-DELÀ du bord de la zone
Config.SpawnSpread = 8.0           -- dispersion aléatoire (m) autour du point d'apparition
Config.OutOfZoneDamage = 8         -- dégâts / seconde pour un défenseur hors de la zone

Config.Teams = {
    A = { label = 'Équipe Rouge', color = '#ff5a5f' },
    B = { label = 'Équipe Bleue', color = '#4ea8ff' },
}

-- Les zones se créent EN JEU avec /editor (admin) : contour point par point,
-- départ des attaquants et des défenseurs. Les zones ci-dessous ne servent que
-- de SECOURS tant qu'aucune zone d'attaque n'a été créée avec l'éditeur.
-- Les zones sont jouées à tour de rôle (une nouvelle zone à chaque match).
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
