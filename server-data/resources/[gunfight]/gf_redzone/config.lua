-- =============================================================================
--  gf_redzone - CONFIGURATION du mode "Redzone"
--
--  Principe : chacun pour soi dans une zone rouge. Réapparition rapide.
--  Seuls les kills faits DANS la zone comptent. La zone active change
--  régulièrement (toutes les zones sont visibles sur la carte).
-- =============================================================================
Config = {}

Config.RespawnDelay = 3        -- secondes avant de réapparaître
Config.SpawnProtection = 3     -- secondes d'invincibilité après l'apparition
Config.RotationMinutes = 15    -- changement de zone toutes les X minutes
Config.OutOfZoneDamage = 10    -- dégâts / seconde hors de la zone active
Config.KillZoneMargin = 15.0   -- tolérance (m) au bord de la zone pour compter un kill
Config.HealOnKill = true       -- le tueur récupère sa vie et son gilet

-- Annonce à tout le monde quand quelqu'un atteint ces séries de kills
Config.StreakAnnounces = { 5, 10, 15, 20 }

-- Zones (la hauteur z est corrigée automatiquement au sol)
Config.Zones = {
    { name = 'Pillbox Hill',   center = vector3(300.0, -590.0, 43.3),    radius = 70.0 },
    { name = 'Vespucci Beach', center = vector3(-1330.0, -1520.0, 4.4),  radius = 90.0 },
    { name = 'Mirror Park',    center = vector3(1100.0, -650.0, 56.8),   radius = 90.0 },
}
