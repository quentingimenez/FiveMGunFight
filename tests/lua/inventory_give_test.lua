-- Test du flux « donner une arme au Casier » (commande /give, export et event admin).
-- Lancement : lua5.4 tests/lua/inventory_give_test.lua  (ou GF_ROOT=<racine> du dépôt).
-- Le serveur est chargé avec loadfile dans un environnement simulé : ni FiveM,
-- ni MySQL, ni dépendance externe. Aucune règle métier n'est recopiée ici.

local root = os.getenv('GF_ROOT') or '.'

local ok = 0

local function check(condition, message)
    if not condition then
        io.stderr:write(('ECHEC : %s\n'):format(tostring(message)))
        os.exit(1)
    end
end

-- ---------------------------------------------------------------------------
-- Faux partagés par la ressource chargée.
-- ---------------------------------------------------------------------------
local licenses = {
    [1] = 'license:admin',
    [2] = 'license:intrus',
    [3] = 'license:cible',
}
local names = {
    [1] = 'Admin',
    [2] = 'Intrus',
    [3] = 'Cible',
}

local registry = {}                     -- [licence][id arme] = true
local writes = {}                       -- { { sql = ..., params = ... }, ... }
local notices = {}                      -- { { src = ..., message = ... }, ... }
local prints = {}                       -- chaînes produites par le print de env
local events = {}                       -- { { name, target, data }, ... }
local handlers, commands, eventHandlers, exported = {}, {}, {}, {}

local clock = 0

local function registryOf(src)
    local id = licenses[src]
    if not id then return nil end
    if not registry[id] then registry[id] = {} end
    return registry[id]
end

local core = {
    IsAdmin = function(_, src) return src == 0 or src == 1 end,
    GetWeaponCatalog = function()
        return {
            { id = 'carbine', name = 'WEAPON_CARBINE', label = 'Carbine', category = 'rifle' },
            { id = 'pistol', name = 'WEAPON_PISTOL', label = 'Pistolet', category = 'pistol' },
        }
    end,
    OwnsWeapon = function(_, src, id)
        if id == 'pistol' then return true end
        local owned = registryOf(src)
        return owned ~= nil and owned[id] == true
    end,
    Notify = function(_, src, message)
        notices[#notices + 1] = { src = src, message = message }
    end,
    GetOwnedWeapons = function() return {} end,
    GetMode = function() return 'lobby' end,
}

local exports = {
    gf_core = core,
    gf_db = { Pret = function() return true end },
}
-- exports('Nom', fn) enregistre la fonction dans exported.
setmetatable(exports, { __call = function(_, name, fn) exported[name] = fn end })

local env = setmetatable({
    source = 1,
    exports = exports,
    MySQL = {
        query = { await = function(_, params)
            local rows = {}
            local owned = params and registry[params[1]]
            if owned then
                for id in pairs(owned) do rows[#rows + 1] = { weapon_id = id } end
            end
            return rows
        end },
        single = { await = function() return nil end },
        prepare = { await = function(sql, params)
            writes[#writes + 1] = { sql = sql, params = params }
            if sql:find('INSERT IGNORE INTO gf_player_weapons', 1, true) then
                local owned = registry[params[1]]
                if not owned then
                    owned = {}
                    registry[params[1]] = owned
                end
                owned[params[2]] = true
            end
        end },
    },
    GetPlayerName = function(src) return names[src] end,
    GetPlayerIdentifiers = function(src)
        local id = licenses[src]
        if id then return { id } end
        return {}
    end,
    GetResourceState = function() return 'started' end,
    GetGameTimer = function() clock = clock + 1000; return clock end,
    GetPlayers = function() return {} end,
    GetCurrentResourceName = function() return 'gf_inventory' end,
    CreateThread = function() end,
    AddEventHandler = function(name, fn) eventHandlers[name] = fn end,
    RegisterNetEvent = function(name, fn) handlers[name] = fn end,
    RegisterCommand = function(name, fn) commands[name] = fn end,
    TriggerClientEvent = function(name, target, data)
        events[#events + 1] = { name = name, target = target, data = data }
    end,
    TriggerEvent = function() end,
    -- Le print du serveur est capturé ; le print du test (hors env) reste réel.
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        prints[#prints + 1] = table.concat(parts, '\t')
    end,
}, { __index = _G })

assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_inventory/server.lua', 't', env))()

local give = assert(commands.give, 'commande /give absente du serveur')

local function noticeIs(index, src, message)
    local notice = notices[index]
    return notice ~= nil and notice.src == src and notice.message == message
end

local function hasNotice(from, src, message)
    for i = from, #notices do
        if notices[i].src == src and notices[i].message == message then return true end
    end
    return false
end

-- 1. Joueur non admin : refus immédiat, sans écriture.
do
    local before, n = #writes, #notices
    give(2, { '3', 'carbine' })
    check(#writes == before, 'cas 1 : aucune écriture attendue')
    check(#notices == n + 1, 'cas 1 : une seule notification attendue')
    check(noticeIs(n + 1, 2, 'Réservé aux administrateurs.'), 'cas 1 : message exact')
    ok = ok + 1
end

-- 2. Admin sans argument : usage, sans écriture.
do
    local before, n = #writes, #notices
    give(1, {})
    check(#writes == before, 'cas 2 : aucune écriture attendue')
    check(#notices == n + 1, 'cas 2 : une seule notification attendue')
    check(noticeIs(n + 1, 1, 'Usage : give <id joueur> <arme> (ex. give 12 carbine).'),
        'cas 2 : message exact')
    ok = ok + 1
end

-- 3. Identifiant de catalogue inconnu : refus, sans écriture.
do
    local before, n = #writes, #notices
    give(1, { '3', 'blaster' })
    check(#writes == before, 'cas 3 : aucune écriture attendue')
    check(#notices == n + 1, 'cas 3 : une seule notification attendue')
    check(noticeIs(n + 1, 1, 'Arme inconnue : blaster (identifiant du catalogue, ex. carbine).'),
        'cas 3 : message exact')
    ok = ok + 1
end

-- 4. Cible déconnectée : refus, sans écriture.
do
    local before, n = #writes, #notices
    give(1, { '9', 'carbine' })
    check(#writes == before, 'cas 4 : aucune écriture attendue')
    check(#notices == n + 1, 'cas 4 : une seule notification attendue')
    check(noticeIs(n + 1, 1, 'Joueur 9 introuvable.'), 'cas 4 : message exact')
    ok = ok + 1
end

-- 5. Attribution réelle (id en majuscules) : une écriture, deux notifications, casier mis à jour.
do
    local before, n = #writes, #notices
    give(1, { '3', 'CARBINE' })
    check(#writes == before + 1, 'cas 5 : exactement une écriture attendue')
    local w = writes[#writes]
    check(w.params[1] == 'license:cible' and w.params[2] == 'carbine' and w.params[3] == 'admin',
        'cas 5 : paramètres d’écriture exacts')
    check(#notices == n + 2, 'cas 5 : deux notifications attendues')
    check(hasNotice(n + 1, 1, 'Carbine ajoutée au Casier de Cible.'), 'cas 5 : message admin exact')
    check(hasNotice(n + 1, 3, 'Carbine ajoutée à ton Casier par un administrateur.'),
        'cas 5 : message cible exact')
    local found = false
    for _, id in ipairs(exported.GetObtained(3)) do
        if id == 'carbine' then found = true end
    end
    check(found, 'cas 5 : carbine présent dans le Casier de la cible')
    ok = ok + 1
end

-- 6. Rejeu de la même commande : aucun doublon en base.
do
    local before, n = #writes, #notices
    give(1, { '3', 'carbine' })
    check(#writes == before, 'cas 6 : aucune nouvelle écriture attendue')
    check(#notices == n + 1, 'cas 6 : une seule notification attendue')
    check(noticeIs(n + 1, 1, 'Cible possède déjà Carbine.'), 'cas 6 : message exact')
    ok = ok + 1
end

-- 7. Arme de départ déjà possédée : aucune écriture.
do
    local before, n = #writes, #notices
    give(1, { '3', 'pistol' })
    check(#writes == before, 'cas 7 : aucune écriture attendue')
    check(#notices == n + 1, 'cas 7 : une seule notification attendue')
    check(noticeIs(n + 1, 1, 'Cible possède déjà Pistolet.'), 'cas 7 : message exact')
    ok = ok + 1
end

-- 8. Console (src 0) : réponse par print, pas de Notify, pas d’écriture.
do
    local before, n, p = #writes, #notices, #prints
    give(0, { '3', 'pistol' })
    check(#writes == before, 'cas 8 : aucune écriture attendue')
    check(#notices == n, 'cas 8 : aucune notification attendue depuis la console')
    check(#prints > p, 'cas 8 : un print attendu')
    check(prints[#prints] == '[gf_inventory] Cible possède déjà Pistolet.', 'cas 8 : print exact')
    ok = ok + 1
end

-- 9. Export direct avec un id inconnu : false, 'unknown', sans écriture.
do
    local giveToLocker = assert(exported.GiveWeaponToLocker, 'export GiveWeaponToLocker absent')
    local before = #writes
    local result, reason = giveToLocker(3, 'inconnue')
    check(result == false and reason == 'unknown', 'cas 9 : retour false, unknown attendu')
    check(#writes == before, 'cas 9 : aucune écriture attendue')
    ok = ok + 1
end

-- 10. Régression du handler adminGive : écriture pour l’admin, notification et données client.
do
    local before, n, e = #writes, #notices, #events
    env.source = 1
    assert(handlers['gf_inventory:adminGive'])('carbine')
    check(#writes == before + 1, 'cas 10 : exactement une écriture attendue')
    local w = writes[#writes]
    check(w.params[1] == 'license:admin' and w.params[2] == 'carbine' and w.params[3] == 'admin',
        'cas 10 : paramètres d’écriture exacts')
    check(#notices == n + 1, 'cas 10 : une seule notification attendue')
    check(noticeIs(n + 1, 1, 'Carbine ajoutée à ton Casier.'), 'cas 10 : message exact')
    local sent = false
    for i = e + 1, #events do
        if events[i].name == 'gf_inventory:adminData' and events[i].target == 1 then sent = true end
    end
    check(sent, 'cas 10 : gf_inventory:adminData envoyé à l’admin')
    ok = ok + 1
end

-- Sécurité finale : aucun identifiant ne fuite dans les messages ou les logs.
for _, notice in ipairs(notices) do
    check(not (notice.message:find('license:', 1, true) or notice.message:find('ip:', 1, true)),
        'fuite d’identifiant dans une notification')
end
for _, line in ipairs(prints) do
    check(not (line:find('license:', 1, true) or line:find('ip:', 1, true)),
        'fuite d’identifiant dans un print')
end

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
