-- =============================================================================
--  Planification des migrations de base de données (module pur, Lua 5.4).
--  Aucune native FiveM, aucun require : module global chargé par dofile.
--  L'entier 0xFFFFFFFF et les opérateurs ~ / & restent dans le domaine des
--  entiers Lua 5.4 (aucun flottant, aucune bibliothèque bit32).
-- =============================================================================

MigrationPlan = {}

local OFFSET_BASIS = 2166136261
local PRIME = 16777619
local MASQUE_32 = 0xFFFFFFFF

-- Normalise les fins de ligne avant tout traitement (CRLF -> LF).
local function normaliserLignes(texte)
    return (texte:gsub('\r\n', '\n'))
end

--- Somme FNV-1a 32 bits d'un texte, en 8 caractères hexadécimaux minuscules.
--- @param texte string
--- @return string
function MigrationPlan.somme(texte)
    local contenu = normaliserLignes(texte)
    local h = OFFSET_BASIS
    for i = 1, #contenu do
        local octet = contenu:byte(i)
        h = (h ~ octet) & MASQUE_32
        h = (h * PRIME) & MASQUE_32
    end
    return ('%08x'):format(h)
end

--- Découpe un script SQL en instructions, une par ligne terminée par ';'.
--- Les lignes entièrement commentées (après espaces de début) et les lignes
--- vides sont ignorées. Un '--' au milieu d'une ligne n'est pas un commentaire.
--- @param sql string
--- @return table liste ordonnée d'instructions
function MigrationPlan.decouper(sql)
    local contenu = normaliserLignes(sql)
    local resultat = {}
    local courant = {}

    local function ajouterInstruction()
        if #courant == 0 then return end
        local instruction = table.concat(courant, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
        if instruction ~= '' then
            resultat[#resultat + 1] = instruction
        end
        courant = {}
    end

    for ligne in contenu:gmatch('[^\n]*') do
        local sansDebut = ligne:gsub('^%s+', '')
        if sansDebut ~= '' and sansDebut:sub(1, 2) ~= '--' then
            courant[#courant + 1] = ligne
            if ligne:match(';%s*$') then
                -- On retire le ';' final (et les espaces qui le suivent).
                local derniere = courant[#courant]:gsub(';%s*$', '')
                courant[#courant] = derniere
                ajouterInstruction()
            end
        end
    end

    -- Robustesse : une dernière instruction non terminée par ';' est gardée.
    ajouterInstruction()
    return resultat
end

--- Construit le plan d'application des migrations.
--- @param connues table liste ordonnée { version = entier, nom = string, somme = string }
--- @param appliquees table table [version] = somme
--- @return table aAppliquer, string|nil erreur
function MigrationPlan.planifier(connues, appliquees)
    local aAppliquer = {}
    appliquees = appliquees or {}

    -- 1. Numérotation : 1, 2, 3, ... sans trou ni doublon.
    for i, migration in ipairs(connues) do
        if type(migration) ~= 'table' or type(migration.version) ~= 'number'
            or migration.version % 1 ~= 0 or migration.version ~= i then
            return {}, 'numerotation'
        end
    end

    -- Versions connues, pour la vérification des versions appliquées.
    local versionsConnues = {}
    for _, migration in ipairs(connues) do
        versionsConnues[migration.version] = true
    end

    -- 2. Version appliquée absente du code (parcours ordonné).
    local trie = {}
    for version in pairs(appliquees) do
        trie[#trie + 1] = version
    end
    table.sort(trie)
    for _, version in ipairs(trie) do
        if not versionsConnues[version] then
            return {}, 'base-plus-recente'
        end
    end

    -- 3. Somme d'une migration appliquée différente de celle du code.
    for _, version in ipairs(trie) do
        if appliquees[version] ~= connues[version].somme then
            return {}, ('migration-modifiee:%d'):format(version)
        end
    end

    -- Plan : toutes les migrations non encore appliquées, dans l'ordre du code.
    for _, migration in ipairs(connues) do
        if appliquees[migration.version] == nil then
            aAppliquer[#aAppliquer + 1] = migration
        end
    end

    return aAppliquer, nil
end
