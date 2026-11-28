-- Changer d'arme ne doit pas recharger les autres armes ni toucher au gilet.
local root = os.getenv('GF_ROOT') or '.'
local events, weapons, current, armour = {}, {}, nil, 0
local dead, mode, componentCalls = false, { gf_mode = 'redzone' }, 0
local stub = function() end
local env = setmetatable({
    Config = { WeaponSlots = 2, Weapons = {}, Loadouts = {} },
    LocalPlayer = { state = mode },
    GlobalState = {},
    exports = setmetatable({}, { __call = stub }),
    joaat = function(name) return name end,
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    RegisterCommand = stub,
    RegisterKeyMapping = stub,
    AddEventHandler = stub,
    CreateThread = stub,
    GetResourceKvpString = stub,
    PlayerPedId = function() return 1 end,
    IsEntityDead = function() return dead end,
    GetSelectedPedWeapon = function() return current end,
    HasPedGotWeapon = function(_, hash) return weapons[hash] ~= nil end,
    RemoveAllPedWeapons = function() weapons = {} end,
    RemoveWeaponFromPed = function(_, hash) weapons[hash] = nil end,
    GiveWeaponToPed = function(_, hash, ammo) weapons[hash] = ammo end,
    SetPedInfiniteAmmo = stub,
    GiveWeaponComponentToPed = function() componentCalls = componentCalls + 1 end,
    RemoveWeaponComponentFromPed = function() componentCalls = componentCalls + 1 end,
    SetCurrentPedWeapon = function(_, hash) current = hash end,
    SetPedArmour = function(_, value) armour = value end,
}, { __index = _G })
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_core/crash_marker.lua', 't', env))()
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_core/client.lua', 't', env))()
events['gf_core:giveWeapons']({ { name = 'A', ammo = 30 }, { name = 'B', ammo = 20, components = { 'SIGHT' } } }, 70)
weapons.B = 4
local before = componentCalls
events['gf_core:updateRedzoneWeapons']({ { name = 'C', ammo = 40 }, { name = 'B', ammo = 20, components = { 'SIGHT' } } })
assert(not weapons.A and weapons.C == 40 and weapons.B == 4, 'remplacement et munitions conservées')
assert(componentCalls == before, 'ne pas retirer les accessoires inchangés')
assert(current == 'C' and armour == 70, 'arme active et gilet')
current = 'B'
events['gf_core:updateRedzoneWeapons']({ { name = 'B', ammo = 20, components = { 'SIGHT' } }, { name = 'C', ammo = 40 } })
assert(current == 'B' and weapons.B == 4 and armour == 70, 'échange des emplacements')
before = componentCalls
events['gf_core:updateRedzoneWeapons']({
    { name = 'B', ammo = 20, removeComponents = { 'SIGHT' }, components = {} },
    { name = 'C', ammo = 40 },
})
assert(componentCalls == before + 1 and weapons.B == 4 and armour == 70, 'modification ciblée des accessoires')
mode.gf_mode = 'attack'
events['gf_core:updateRedzoneWeapons']({ { name = 'D', ammo = 10 } })
assert(not weapons.D and weapons.B == 4, 'aucun changement en attaque')
mode.gf_mode, dead = 'redzone', true
events['gf_core:updateRedzoneWeapons']({ { name = 'D', ammo = 10 } })
assert(not weapons.D, 'aucun changement pendant la mort')
print('Changement Redzone : armes, munitions, gilet et modes vérifiés')
