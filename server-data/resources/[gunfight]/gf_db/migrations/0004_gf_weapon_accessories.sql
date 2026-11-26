-- Un choix d'accessoires par joueur et par arme du catalogue.
CREATE TABLE IF NOT EXISTS gf_weapon_accessories (
    identifier VARCHAR(64) NOT NULL,
    weapon_id VARCHAR(48) NOT NULL,
    selections TEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (identifier, weapon_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
