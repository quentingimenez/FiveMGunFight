-- =============================================================================
--  gf_redzone - CONFIGURATION du mode "Redzone"
--
--  Principe : une seule partie en cours à la fois (10 min par défaut).
--  Les joueurs apparaissent À PIED près de la zone. Ils vont au point véhicule
--  (marqueur bleu), appuient sur E pour être placés dans leur voiture, roulent
--  jusqu'à la zone, appuient sur F : la voiture disparaît et ils se battent.
--  On ne peut tirer et être touché QUE dans la zone.
--  À la mort, retour au point d'apparition, à pied.
--
--  Les maps se créent en jeu avec /editor (admin), et se cochent / décochent
--  dans la même fenêtre (/maps). Tant qu'aucune map n'est cochée, les zones de
--  secours ci-dessous (Config.Zones) sont utilisées.
-- =============================================================================
Config = {}

Config.GameDuration = 600      -- durée d'une partie en secondes (600 = 10 min)
Config.EndDelay = 15           -- pause entre deux parties (classement final)
Config.RespawnDelay = 3        -- secondes avant de réapparaître
Config.Vehicle = 'theramtrx21' -- véhicule des points véhicule (Dodge Ram TRX, ressource gf_vehicles)
Config.KillZoneMargin = 15.0   -- tolérance (m) au bord de la zone pour compter un kill
Config.HealOnKill = true       -- le tueur récupère sa vie et son gilet

-- Annonce à tout le monde quand quelqu'un atteint ces séries de kills
Config.StreakAnnounces = { 5, 10, 15, 20 }

-- Zones de secours (utilisées seulement si aucune map n'a été créée avec /editor).
-- Les points de départ sont générés automatiquement autour du cercle.
Config.Zones = {
    { name = 'Pillbox Hill',   center = vector3(300.0, -590.0, 43.3),   radius = 70.0 },
    { name = 'Vespucci Beach', center = vector3(-1330.0, -1520.0, 4.4), radius = 90.0 },
    { name = 'Mirror Park',    center = vector3(1100.0, -650.0, 56.8),  radius = 90.0 },
}
