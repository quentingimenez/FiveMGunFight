-- Le serveur doit refuser le changement dans la zone, avant toute écriture.
local root = os.getenv('GF_ROOT') or '.'
local handlers, writes, emitted, notices = {}, 0, {}, {}
local mode, allowed, clock = 'redzone', false, 0
local core = {
    OwnsWeapon = function() return true end,
    GetMode = function() return mode end,
    ResolveSelection = function() return { 'carbine', 'pistol' } end,
    GetOwnedWeapons = function() return {} end,
    Notify = function(_, _, message) notices[#notices + 1] = message end,
}
local env = setmetatable({
    source = 1,
    exports = { gf_core = core, gf_db = { Pret = function() return true end },
        gf_redzone = { CanChangeWeapons = function() return allowed end } },
    MySQL = {
        query = { await = function() return {} end },
        single = { await = function() return nil end },
        prepare = { await = function() writes = writes + 1 end },
    },
    GetPlayerIdentifiers = function() return { 'license:example' } end,
    GetPlayerName = function() return 'Joueur' end,
    GetResourceState = function() return 'started' end,
    GetGameTimer = function() clock = clock + 1000 return clock end,
    RegisterNetEvent = function(name, fn) handlers[name] = fn end,
    RegisterCommand = function() end,
    AddEventHandler = function() end,
    TriggerClientEvent = function() end,
    TriggerEvent = function(name) emitted[#emitted + 1] = name end,
}, { __index = _G })
setmetatable(env.exports, { __call = function() end })
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_inventory/server.lua', 't', env))()
local equip = assert(handlers['gf_inventory:equip'])
equip(1, 'new')
assert(writes == 0 and #emitted == 0 and #notices == 1, 'zone de combat : refus')
allowed = true
equip(1, 'new')
assert(writes == 1 and emitted[1] == 'gf_inventory:selectionChanged', 'hors zone : sauvegarde')
mode, allowed = 'attack', false
equip(1, 'new')
assert(writes == 2, 'attaque : le casier reste enregistrable')
print('Casier : refus en zone, sauvegarde hors zone et attaque vérifiés')
