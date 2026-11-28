local root = os.getenv('GF_ROOT') or '.'
local base = root .. '/server-data/resources/[gunfight]/'
local handlers, localEvents, exported, changes, saves = {}, {}, {}, 0, 0
local stored
local mode, outside, tick = 'redzone', false, 0
local core = {
    OwnsWeapon = function(_, _, id) return id == 'special' end,
    GetOwnedWeapons = function() return { { id = 'special', name = 'WEAPON_SPECIALCARBINE' } } end,
    GetMode = function() return mode end,
    Notify = function() end,
}
local ex = { gf_core = core, gf_db = { Pret = function() return true end },
    gf_redzone = { CanChangeWeapons = function() return outside end },
    gf_weapons = { GetWeaponMeta = function(_, name) return nil end } }
setmetatable(ex, { __call = function(_, name, fn) exported[name] = fn end })
local env = setmetatable({
    exports = ex, source = 1,
    json = { encode = function(value) stored = value return 'stored' end, decode = function() return stored end },
    MySQL = { query = { await = function(query)
        if query:find('gf_weapon_accessories', 1, true) and stored then
            return { { weapon_id = 'special', selections = 'stored' } }
        end
        return {}
    end }, single = { await = function() end },
        prepare = { await = function() saves = saves + 1 end } },
    GetResourceState = function() return 'started' end,
    GetPlayerIdentifiers = function() return { 'license:test' } end,
    GetPlayerName = function() return 'Test' end,
    GetGameTimer = function() tick = tick + 1000 return tick end,
    RegisterNetEvent = function(name, fn) handlers[name] = fn end,
    RegisterCommand = function() end, AddEventHandler = function(name, fn) localEvents[name] = fn end,
    TriggerClientEvent = function() end,
    TriggerEvent = function(name) if name == 'gf_inventory:selectionChanged' then changes = changes + 1 end end,
    LoadResourceFile = function() end,
}, { __index = _G })
assert(loadfile(base .. 'gf_inventory/accessories.lua', 't', env))()
assert(loadfile(base .. 'gf_inventory/server.lua', 't', env))()
local set = assert(handlers['gf_inventory:setAccessories'])
set('special', { sight = 'COMPONENT_AT_SCOPE_MEDIUM' })
assert(saves == 0, 'zone de combat : écriture refusée')
outside = true
set('special', { sight = 'COMPONENT_AT_PI_SUPP' })
assert(saves == 0, 'composant incompatible refusé')
set('other', { sight = 'COMPONENT_AT_SCOPE_MEDIUM' })
assert(saves == 0, 'arme non possédée refusée')
set('special', { sight = 'COMPONENT_AT_SCOPE_MEDIUM' })
assert(saves == 1 and changes == 1, 'choix valide enregistré')
local remove, add = exported.GetWeaponAccessories(1, 'special', 'WEAPON_SPECIALCARBINE')
assert(#remove == 1 and remove[1] == 'COMPONENT_AT_SCOPE_MEDIUM' and add[1] == remove[1], 'composant transmis')
mode = 'attack'
set('special', { sight = '' })
assert(saves == 2, 'choix enregistrable en attaque')
localEvents.playerDropped()
handlers['gf_inventory:requestLocker']()
remove, add = exported.GetWeaponAccessories(1, 'special', 'WEAPON_SPECIALCARBINE')
assert(#remove == 1 and #add == 0, 'choix restauré après reconnexion')
print('Accessoires : propriété, zone, validation et application serveur vérifiées')
