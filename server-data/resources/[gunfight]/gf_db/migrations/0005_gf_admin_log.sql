-- Journal des actions d'administration.
CREATE TABLE IF NOT EXISTS gf_admin_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    admin_identifier VARCHAR(64) NULL,
    admin_name VARCHAR(64) NOT NULL,
    action VARCHAR(32) NOT NULL,
    target_identifier VARCHAR(64) NULL,
    target_name VARCHAR(64) NULL,
    details VARCHAR(255) NULL,
    INDEX idx_gf_admin_log_created_at (created_at)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_unicode_ci;
