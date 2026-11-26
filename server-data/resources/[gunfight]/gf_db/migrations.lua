-- =============================================================================
--  gf_db - MIGRATIONS CONNUES
--  Une seule entrée par version, dans l'ordre d'application.
--  La somme est calculée à partir du fichier SQL par MigrationPlan.somme().
-- =============================================================================

Migrations = {
    { version = 1, nom = 'gf_stats_players', fichier = 'migrations/0001_gf_stats_players.sql' },
    { version = 2, nom = 'gf_match_events', fichier = 'migrations/0002_gf_match_events.sql' },
    { version = 3, nom = 'gf_player_weapons', fichier = 'migrations/0003_gf_player_weapons.sql' },
}
