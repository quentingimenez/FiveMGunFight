-- =============================================================================
--  gf_admin - JOURNAL D'AUDIT (serveur)
--  Trace les actions d'administration dans gf_admin_log. Aucun identifiant
--  (license, IP, Discord) n'est écrit dans les journaux texte : ils ne
--  transitent que vers la base, sous forme de paramètres liés.
-- =============================================================================

local RESOURCE = 'gf_admin'
local COLONNES = '(admin_identifier, admin_name, action, target_identifier, target_name, details)'
local MAX_ACTION = 32
local MAX_DETAILS = 255

--- Coupe une chaîne à MAX_DETAILS caractères.
local function tronquer(texte)
    if #texte > MAX_DETAILS then return texte:sub(1, MAX_DETAILS) end
    return texte
end

--- Premier identifiant `license:` d'un joueur, ou nil. Les autres préfixes
--- (fivem, ip, discord...) sont ignorés. La native peut renvoyer nil ou
--- autre chose qu'une table : on ne parcourt que les tables.
local function licenseOf(src)
    local ok, ids = pcall(GetPlayerIdentifiers, src)
    if not ok or type(ids) ~= 'table' then return nil end
    for _, id in ipairs(ids) do
        if type(id) == 'string' and id:find('^license:') then return id end
    end
    return nil
end

--- Nom lisible d'un joueur, avec repli si la native ne répond pas.
local function nameOf(src)
    local ok, name = pcall(GetPlayerName, src)
    if ok and name ~= nil then return name end
    return 'joueur ' .. tostring(src)
end

--- Construit l'INSERT : le mot-clé SQL NULL pour les valeurs absentes, un `?`
--- et un paramètre lié seulement pour les valeurs présentes. On évite ainsi
--- les trous nil dans le tableau de paramètres (même procédé que gf_journal).
--- Seuls des noms de colonnes, `?` et `NULL` sont concaténés au SQL.
local function inserter(valeurs)
    local champs, params = {}, {}
    for i = 1, 6 do
        local valeur = valeurs[i]
        if valeur == nil then
            champs[#champs + 1] = 'NULL'
        else
            champs[#champs + 1] = '?'
            params[#params + 1] = valeur
        end
    end
    local requete = ('INSERT INTO gf_admin_log %s VALUES (%s)'):format(
        COLONNES, table.concat(champs, ', '))
    return requete, params
end

--- gf_db doit être démarré ET prêt. Toute erreur (export absent, exception)
--- est absorbée : pas d'écriture, pas d'erreur remontée à l'appelant.
local function pret()
    local ok, ready = pcall(function()
        return GetResourceState('gf_db') == 'started' and exports.gf_db:Pret() == true
    end)
    return ok and ready == true
end

--- Écriture asynchrone (pas de .await), entièrement protégée.
local function ecrire(valeurs)
    if not pret() then return end
    local requete, params = inserter(valeurs)
    pcall(function()
        MySQL.insert(requete, params)
    end)
end

--- Export public : src (0 = console), action, cible et détails facultatifs.
exports('LogAction', function(src, action, target, details)
    -- Validation stricte : refus silencieux, sans print et sans écriture.
    if type(action) ~= 'string' or #action < 1 or #action > MAX_ACTION
        or not action:find('^[a-z_]+$') then
        return
    end

    local adminName, adminIdentifier
    if src == 0 then
        adminName = 'console'
    else
        adminName = nameOf(src)
        adminIdentifier = licenseOf(src)
    end

    -- La cible est un id joueur, éventuellement fourni en chaîne numérique.
    local targetId = tonumber(target)
    local targetName, targetIdentifier
    if targetId and targetId > 0 then
        local ok, name = pcall(GetPlayerName, targetId)
        if ok and name ~= nil then
            targetName = name
            targetIdentifier = licenseOf(targetId)
        end
    end

    local detailTexte
    if details ~= nil then
        local ok, texte = pcall(tostring, details)
        if ok then detailTexte = tronquer(texte) end
    end

    -- Journal texte court : noms et action seulement, jamais d'identifiant.
    local parts = { '[' .. RESOURCE .. ']', adminName, action }
    if targetName then parts[#parts + 1] = targetName end
    if detailTexte then parts[#parts + 1] = detailTexte end
    print(table.concat(parts, ' '))

    ecrire({ adminIdentifier, adminName, action, targetIdentifier, targetName, detailTexte })
end)
