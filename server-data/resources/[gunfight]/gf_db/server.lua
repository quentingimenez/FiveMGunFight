-- =============================================================================
--  gf_db - SERVEUR
--  MariaDB valide implicitement chaque instruction DDL, donc une migration doit
--  être idempotente (IF NOT EXISTS) pour pouvoir être rejouée après un échec
--  partiel ; la somme détecte une migration déjà appliquée qui aurait été
--  modifiée.
--  Les exports sont définis avant l'attente d'oxmysql pour être disponibles
--  immédiatement (gf_stats les interroge dès son propre démarrage).
-- =============================================================================

local pret = false
local versionAppliquee = nil

exports('Pret', function()
    return pret
end)

exports('Version', function()
    return versionAppliquee
end)

-- Table de version : créée une seule fois, avant toute lecture.
local SQL_VERSION = [[
CREATE TABLE IF NOT EXISTS gf_schema_version (
    version INT UNSIGNED NOT NULL PRIMARY KEY,
    nom VARCHAR(190) NOT NULL,
    somme CHAR(8) NOT NULL,
    appliquee_le TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4
]]

CreateThread(function()
    local ok, err = pcall(function()
        -- .await() attend réellement la connexion oxmysql ; l'appel MySQL.ready()
        -- seul rend la main immédiatement (Citizen.CreateThreadNow) et laisserait
        -- partir la première requête avant la création du pool.
        MySQL.ready.await()

        MySQL.query.await(SQL_VERSION)

        -- Versions déjà appliquées : [version] = somme.
        local appliquees = {}
        local lignes = MySQL.query.await('SELECT version, somme FROM gf_schema_version')
        for _, ligne in ipairs(lignes or {}) do
            appliquees[tonumber(ligne.version)] = ligne.somme
        end

        -- Lectures des fichiers une seule fois ; le SQL est conservé par version
        -- pour ne pas relire le disque au moment de l'application.
        local contenus = {}
        local connues = {}
        for _, m in ipairs(Migrations) do
            local contenu = LoadResourceFile(GetCurrentResourceName(), m.fichier)
            if not contenu then
                error(('fichier de migration introuvable : %s'):format(m.fichier))
            end
            local somme = MigrationPlan.somme(contenu)
            contenus[m.version] = contenu
            connues[#connues + 1] = { version = m.version, nom = m.nom, somme = somme }
        end

        local aAppliquer, erreur = MigrationPlan.planifier(connues, appliquees)
        if erreur then
            error(('planification impossible : %s'):format(tostring(erreur)))
        end

        -- Dernière version déjà en base (0 si la table de version est vide).
        local version = 0
        for v in pairs(appliquees) do
            if v > version then version = v end
        end

        for _, m in ipairs(aAppliquer) do
            local instructions = MigrationPlan.decouper(contenus[m.version])
            if #instructions == 0 then
                error(('migration %04d vide'):format(m.version))
            end
            for _, instruction in ipairs(instructions) do
                MySQL.query.await(instruction)
            end
            MySQL.insert.await('INSERT INTO gf_schema_version (version, nom, somme) VALUES (?, ?, ?)', { m.version, m.nom, m.somme })
            version = m.version
            print(('[gf_db] migration %04d %s appliquée'):format(m.version, m.nom))
        end

        print(('[gf_db] schéma à jour (version %d)'):format(version))
        GlobalState.gf_db_version = version
        -- L'état doit être visible avant l'événement : un gestionnaire de
        -- gf_db:pret qui appelle l'export Pret() doit lire true.
        pret = true
        versionAppliquee = version
        TriggerEvent('gf_db:pret', version)
    end)

    if not ok then
        print(('[gf_db] ERREUR %s'):format(tostring(err)))
    end
end)
