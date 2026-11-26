-- Teste la commande à travers le vrai serveur et les règles d'Attaque.
local root = os.getenv('GF_ROOT') or '.'
local resource = root .. '/server-data/resources/[gunfight]/gf_attack/'
local handlers, commands, messages = {}, {}, {}
local players, modes, teams = {}, {}, {}
local failTarget = false
local core = {}
local env = setmetatable({
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    GetPlayerName = function(src) return players[src] and ('Joueur ' .. src) or nil end,
    GetGameTimer = function() return 10000 end,
    GetCurrentResourceName = function() return 'gf_attack' end,
    GetPlayerPed = function() return 0 end,
    Player = function() return { state = { set = function() end } } end,
    CreateThread = function() end,
    SetTimeout = function() end,
    TriggerClientEvent = function() end,
    RegisterNetEvent = function(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
    AddEventHandler = function(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
    RegisterCommand = function(name, fn) commands[name] = fn end,
}, { __index = _G })

local function event(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
env.TriggerEvent = event
function core:IsAdmin(src) return src == 1 end
function core:GetMode(src) return modes[src] end
function core:Notify(src, message) messages[src] = message end
function core:SetTeam(src, team) teams[src] = team end
function core:Spawn() end
function core:SetProtected() end
function core:GetSelectionSettings() return { count = 2, armour = 100 } end
function core:GetOwnedWeapons() return {} end
function core:ResolveSelection() return {} end
function core:SetMode(src, mode)
    if failTarget and src == 2 and mode == 'attack' then return false end
    local old = modes[src]
    if old == mode then return false end
    if old then event('gf:modeLeft', src, old) end
    modes[src] = mode
    event('gf:modeJoined', src, mode)
    return true
end
env.exports = setmetatable({
    gf_core = core,
    gf_maps = { GetActiveMaps = function() return {} end },
}, { __call = function() end })

assert(loadfile(resource .. 'config.lua', 't', env))()
assert(loadfile(resource .. 'rules.lua', 't', env))()
assert(loadfile(resource .. 'server.lua', 't', env))()
players[1], players[2], players[3] = true, true, true
modes[1], modes[2], modes[3] = 'lobby', 'lobby', 'lobby'

commands.testattaque(2, { '1' })
assert(modes[1] == 'lobby' and modes[2] == 'lobby', 'un joueur non admin ne lance pas le test')
commands.testattaque(1, { '1' })
assert(modes[1] == 'lobby', 'un joueur ne peut pas se choisir lui-même')
commands.testattaque(1, { '999' })
assert(modes[1] == 'lobby', 'un joueur absent est refusé')
modes[2] = 'redzone'
commands.testattaque(1, { '2' })
assert(modes[1] == 'lobby' and modes[2] == 'redzone', 'une partie Redzone reste intacte')
modes[2] = 'lobby'
core:SetMode(3, 'attack')
commands.testattaque(1, { '2' })
assert(modes[1] == 'lobby' and modes[2] == 'lobby', 'les autres participants sont protégés')
core:SetMode(3, 'lobby')
failTarget = true
commands.testattaque(1, { '2' })
assert(modes[1] == 'lobby' and modes[2] == 'lobby', 'un échec remet le premier joueur au lobby')
failTarget = false
commands.testattaque(1, { '2' })
assert(modes[1] == 'attack' and modes[2] == 'attack', 'les deux joueurs rejoignent le mode')
assert(teams[1] and teams[2] and teams[1] ~= teams[2], 'les équipes sont opposées')
commands.testattaque(1, { '2' })
assert(messages[1] == 'Un match est déjà en cours.', 'un match actif ne peut pas être remplacé')
print('Test Attaque 1 contre 1 : équipes, permissions et échecs vérifiés')
