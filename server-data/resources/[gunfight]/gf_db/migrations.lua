-- =============================================================================
--  gf_db - MIGRATIONS CONNUES
--  Une seule entrée par version, dans l'ordre d'application.
--  La somme est calculée à partir du fichier SQL par MigrationPlan.somme().
-- =============================================================================

Migrations = {
    { version = 1, nom = 'gf_stats_players', fichier = 'migrations/0001_gf_stats_players.sql' },
}
