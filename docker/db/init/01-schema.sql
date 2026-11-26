-- =============================================================================
--  Schéma des statistiques persistantes (gf_stats)
--  Exécuté une seule fois par MariaDB, au premier démarrage du volume vide.
--  Voir docker/db/init/README.md.
-- =============================================================================

CREATE TABLE IF NOT EXISTS gf_stats_players (
    identifier   VARCHAR(64)  NOT NULL,
    display_name VARCHAR(64)  NOT NULL DEFAULT '',
    kills        INT UNSIGNED NOT NULL DEFAULT 0,
    deaths       INT UNSIGNED NOT NULL DEFAULT 0,
    matches      INT UNSIGNED NOT NULL DEFAULT 0,
    wins         INT UNSIGNED NOT NULL DEFAULT 0,
    first_seen   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier),
    KEY idx_kills (kills),
    KEY idx_wins (wins)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;
