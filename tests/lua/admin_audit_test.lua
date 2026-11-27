-- Test de l'export serveur gf_admin:LogAction (journal d'audit).
-- Lancement : lua5.4 tests/lua/admin_audit_test.lua  (ou GF_ROOT=<racine> du dépôt).
-- audit.lua est chargé avec loadfile dans un environnement simulé : ni FiveM,
-- ni MySQL, ni dépendance externe. Aucune règle métier n'est recopiée ici.

local root = os.getenv('GF_ROOT') or '.'

local ok = 0

local function check(condition, message)
    if not condition then
        io.stderr:write(('ECHEC : %s\n'):format(tostring(message)))
        os.exit(1)
    end
end

local COLONNES = '(admin_identifier, admin_name, action, target_identifier, target_name, details)'

local licenses = {
    [1] = 'license:admin',
    [2] = 'license:cible',
}
local names = {
    [1] = 'Admin',
    [2] = 'Cible',
    [7] = 'SansIdentifiant',
    [8] = 'IdentifiantBizarre',
}

local writes = {}                       -- { { sql = ..., params = ... }, ... }
local prints = {}                       -- lignes produites par le print de env
local exported = {}
local dbState = 'started'
local dbReady = true
local insertError = nil

local exports = setmetatable({
    gf_db = { Pret = function() return dbReady end },
}, {
    -- exports('Nom', fn) enregistre la fonction dans exported.
    __call = function(_, name, fn) exported[name] = fn end,
})

local env = setmetatable({
    exports = exports,
    MySQL = {
        insert = function(sql, params)
            if insertError then error(insertError) end
            writes[#writes + 1] = { sql = sql, params = params }
        end,
    },
    GetResourceState = function(resource)
        return resource == 'gf_db' and dbState or 'started'
    end,
    GetPlayerName = function(src) return names[src] end,
    GetPlayerIdentifiers = function(src)
        if src == 7 then return nil end
        if src == 8 then return 'license:pas-une-table' end
        local id = licenses[src]
        if not id then return {} end
        -- Le préfixe license n'est pas le premier : il ne doit pas être ignoré au profit de fivem/ip.
        return { 'fivem:' .. tostring(src), id, 'ip:1.2.3.4' }
    end,
    -- Le print du serveur est capturé ; le print du test (hors env) reste réel.
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        prints[#prints + 1] = table.concat(parts, ' ')
    end,
}, { __index = _G })

assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_admin/audit.lua', 't', env))()
local logAction = assert(exported.LogAction, 'export LogAction absent')

--- Vérifie la requête et les paramètres réellement passés à MySQL.insert.
--- attendues[i] == nil signifie NULL dans le SQL et aucun paramètre ajouté.
local function expectWrite(write, attendues, label)
    check(write ~= nil, label .. ' : un insert est attendu')
    check(type(write.sql) == 'string' and write.sql:find(COLONNES, 1, true) ~= nil,
        label .. ' : liste de colonnes exacte')
    check(type(write.params) == 'table', label .. ' : paramètres sous forme de table')

    local group = write.sql:match('VALUES%s+(%b())')
    check(group ~= nil, label .. ' : clause VALUES absente')
    local champs = {}
    for champ in group:gmatch('[^(),%s]+') do champs[#champs + 1] = champ end
    check(#champs == 6, label .. ' : 6 valeurs attendues dans VALUES')

    local params = {}
    for i = 1, 6 do
        local valeur = attendues[i]
        local voulu = valeur == nil and 'NULL' or '?'
        check(champs[i] == voulu, ('%s : valeur %d attendue %s, obtenue %s'):format(
            label, i, voulu, tostring(champs[i])))
        if valeur ~= nil then params[#params + 1] = valeur end
    end
    check(#write.params == #params, ('%s : %d paramètres attendus, %d obtenus'):format(
        label, #params, #write.params))
    for i = 1, #params do
        check(write.params[i] == params[i], ('%s : paramètre %d incorrect'):format(label, i))
    end
end

-- a) Actions invalides : refus silencieux, ni insert ni print.
do
    for _, action in ipairs({ 'Majuscule', 'tiret-', '', string.rep('a', 33) }) do
        local before, p = #writes, #prints
        logAction(1, action, 2, 'details')
        check(#writes == before, 'cas a : aucun insert pour une action invalide')
        check(#prints == p, 'cas a : aucun print pour une action invalide')
    end
    ok = ok + 1
end

-- b) Console (src 0) : nom 'console', identifiant nil, cible nil puis 0.
do
    local before, p = #writes, #prints
    logAction(0, 'console_action')
    check(#writes == before + 1 and #prints == p + 1, 'cas b : un insert et un print')
    expectWrite(writes[#writes], { nil, 'console', 'console_action' }, 'cas b')
    check(prints[#prints] == '[gf_admin] console console_action', 'cas b : print exact')

    logAction(0, 'console_action', 0)
    check(#writes == before + 2 and #prints == p + 2, 'cas b : insert et print pour target 0')
    expectWrite(writes[#writes], { nil, 'console', 'console_action' }, 'cas b (target 0)')
    check(prints[#prints] == '[gf_admin] console console_action', 'cas b : print identique')
    ok = ok + 1
end

-- c) Joueur avec cible connectée (id numérique puis chaîne numérique).
do
    local before, p = #writes, #prints
    logAction(1, 'give_weapon', 2, 'carbine')
    check(#writes == before + 1 and #prints == p + 1, 'cas c : un insert et un print')
    expectWrite(writes[#writes], {
        'license:admin', 'Admin', 'give_weapon', 'license:cible', 'Cible', 'carbine',
    }, 'cas c')
    check(prints[#prints] == '[gf_admin] Admin give_weapon Cible carbine',
        'cas c : print exact, sans license')

    logAction(1, 'give_weapon', '2', 'carbine')
    expectWrite(writes[#writes], {
        'license:admin', 'Admin', 'give_weapon', 'license:cible', 'Cible', 'carbine',
    }, 'cas c (cible en chaîne)')

    -- GetPlayerIdentifiers nil ou non-table : aucun identifiant retenu, pas d'erreur.
    logAction(7, 'no_ids')
    expectWrite(writes[#writes], { nil, 'SansIdentifiant', 'no_ids' }, 'cas c (ids nil)')
    logAction(8, 'bad_ids')
    expectWrite(writes[#writes], { nil, 'IdentifiantBizarre', 'bad_ids' }, 'cas c (ids non-table)')
    ok = ok + 1
end

-- d) Détails trop longs : 255 caractères en base et dans le print.
do
    local long = string.rep('x', 300)
    local court = string.rep('x', 255)
    local before, p = #writes, #prints
    logAction(1, 'long_action', nil, long)
    check(#writes == before + 1 and #prints == p + 1, 'cas d : un insert et un print')
    expectWrite(writes[#writes], {
        'license:admin', 'Admin', 'long_action', nil, nil, court,
    }, 'cas d')
    check(prints[#prints] == '[gf_admin] Admin long_action ' .. court, 'cas d : print tronqué')
    ok = ok + 1
end

-- e) Base non prête : aucun insert mais un print, sans erreur propagée.
do
    local before, p = #writes, #prints
    dbState = 'stopped'
    logAction(1, 'no_db', 2, 'details')
    dbState = 'started'
    check(#writes == before, 'cas e : aucun insert si gf_db arrêté')
    check(#prints == p + 1, 'cas e : print malgré gf_db arrêté')

    dbReady = false
    logAction(1, 'no_db', 2, 'details')
    dbReady = true
    check(#writes == before, 'cas e : aucun insert si Pret() faux')
    check(#prints == p + 2, 'cas e : print malgré Pret() faux')
    ok = ok + 1
end

-- f) MySQL.insert lève une erreur : appel direct (sans pcall externe), rien ne
-- propage, le print reste présent.
do
    local before, p = #writes, #prints
    insertError = 'panne MySQL simulée'
    logAction(1, 'db_fail', 2, 'details')
    insertError = nil
    check(#writes == before, 'cas f : aucun insert enregistré')
    check(#prints == p + 1, 'cas f : print présent malgré l’erreur MySQL')
    check(prints[#prints] == '[gf_admin] Admin db_fail Cible details', 'cas f : print exact')
    ok = ok + 1
end

-- g) Cible déconnectée : identifiant et nom nil, print sans nom de cible.
do
    local before, p = #writes, #prints
    logAction(1, 'offline_target', 9, 'x')
    check(#writes == before + 1 and #prints == p + 1, 'cas g : un insert et un print')
    expectWrite(writes[#writes], {
        'license:admin', 'Admin', 'offline_target', nil, nil, 'x',
    }, 'cas g')
    check(prints[#prints] == '[gf_admin] Admin offline_target x', 'cas g : print sans cible')
    ok = ok + 1
end

-- h) Sécurité finale : aucun identifiant ne fuit dans les journaux texte.
do
    for _, line in ipairs(prints) do
        check(not line:find('license:', 1, true), 'cas h : fuite de license dans un print')
        check(not line:find('ip:', 1, true), 'cas h : fuite d’ip dans un print')
    end
    ok = ok + 1
end

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
