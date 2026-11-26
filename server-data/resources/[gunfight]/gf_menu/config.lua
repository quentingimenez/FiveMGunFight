-- =============================================================================
--  gf_menu - CONFIGURATION
--  Valeurs partagées client/serveur pour le menu pause. Les durées sont en
--  millisecondes (suffixe Ms) et se mesurent avec GetGameTimer().
-- =============================================================================

Config = {}

Config.ServerName = 'GUNFIGHT'
Config.BuildFallback = 'dev'

Config.ToggleControl = 200          -- INPUT_FRONTEND_PAUSE (Échap)
Config.ReopenDelayMs = 400          -- anti double appui après fermeture
Config.StateCooldownMs = 500        -- une demande d'état par joueur
Config.QuitCooldownMs = 1000        -- anti double déconnexion
Config.StatsCacheMs = 5000          -- durée de vie du cache de lecture gf_stats
Config.StatsTimeoutMs = 2000        -- réponse gf_stats attendue avant fallback
Config.PageReadyTimeoutMs = 5000    -- page NUI muette = focus rendu
Config.MaxPlayersFallback = 48      -- défaut FXServer (joueurs), si sv_maxclients absent

Config.QuitReason = 'À bientôt sur GUNFIGHT.'
Config.DiscordUrl = ''              -- vide = bouton désactivé, ne rien inventer

-- Libellés affichés pour le mode courant. Une valeur inconnue tombe sur
-- ModeLabelFallback ; l'absence de mode sur ModeLabelIdle.
Config.ModeLabels = {
    lobby = 'DANS LE LOBBY',
    attack = 'ATTAQUE DE ZONE',
    redzone = 'REDZONE',
}
Config.ModeLabelFallback = 'EN PARTIE'
Config.ModeLabelIdle = 'HORS PARTIE'

-- Sections pas encore livrées : la NUI les affiche « BIENTÔT ».
Config.Features = {
    loadout = false,
    crosshair = false,
    shop = false,
    crates = false,
    battlepass = false,
    contributor = false,
    gameSettings = false,
}

-- Règles générales affichées dans le menu. Aucune sanction chiffrée : le
-- serveur n'a pas de politique de sanction documentée ici.
Config.Rules = {
    {
        title = 'Fair-play',
        lines = { 'Joue dans le respect des règles du serveur.' },
    },
    {
        title = 'Pas de triche',
        lines = { 'N’utilise ni exploit ni outil tiers pour prendre un avantage.' },
    },
    {
        title = 'Respect entre joueurs',
        lines = { 'Pas de harcèlement ni de provocation. Traite les autres joueurs avec respect.' },
    },
    {
        title = 'Signalement',
        lines = { 'Un problème ou un joueur à signaler ? Passe par Discord.' },
    },
}
