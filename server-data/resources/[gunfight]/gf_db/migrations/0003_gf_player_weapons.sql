-- Armes obtenues par chaque joueur (en plus des armes de départ de gf_core)
-- et armes équipées dans le Casier (emplacements des touches 1 et 2).
CREATE TABLE IF NOT EXISTS gf_player_weapons (
    identifier  VARCHAR(64) NOT NULL,
    weapon_id   VARCHAR(48) NOT NULL,
    origin      VARCHAR(16) NOT NULL DEFAULT 'admin',
    obtained_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier, weapon_id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gf_player_loadout (
    identifier VARCHAR(64) NOT NULL,
    slot1      VARCHAR(48) NULL,
    slot2      VARCHAR(48) NULL,
    updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci;
