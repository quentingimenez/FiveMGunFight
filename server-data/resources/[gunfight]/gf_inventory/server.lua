-- Inventaire persistant : les choix et les attributions sont validés côté serveur.
local core = exports.gf_core
local cache, busy, lastAction = {}, {}, {}

local function identifierOf(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('^license:') then return id end
    end
end

local function ready()
    return GetResourceState('gf_db') == 'started' and exports.gf_db:Pret()
end

local function load(src)
    local id = identifierOf(src)
    if not id or not ready() then return nil end
    local old = cache[src]
    if old and old.id == id then return old end
    local rows = MySQL.query.await('SELECT weapon_id FROM gf_player_weapons WHERE identifier = ?', { id })
    local selection = MySQL.single.await('SELECT slot1, slot2 FROM gf_player_loadout WHERE identifier = ?', { id })
    if not GetPlayerName(src) or identifierOf(src) ~= id then return nil end
    local entry = { id = id, obtained = {}, slots = {} }
    for _, row in ipairs(rows or {}) do entry.obtained[row.weapon_id] = true end
    if selection then entry.slots = { selection.slot1, selection.slot2 } end
    cache[src] = entry
    return entry
end

local function withInventory(src, action)
    if not GetPlayerName(src) or busy[src] then return end
    local now = GetGameTimer()
    if lastAction[src] and now - lastAction[src] < 300 then return end
    lastAction[src], busy[src] = now, true
    local ok, err = pcall(function()
        local entry = load(src)
        if not entry then
            core:Notify(src, 'Inventaire indisponible. Réessaie dans un instant.')
            return
        end
        action(entry)
    end)
    busy[src] = nil
    if not ok then
        print(('[gf_inventory] erreur de base : %s'):format(tostring(err)))
        if GetPlayerName(src) then core:Notify(src, 'Inventaire indisponible. Réessaie dans un instant.') end
    end
end

local function lockerData(src, entry)
    return { weapons = core:GetOwnedWeapons(src), slot1 = entry.slots[1], slot2 = entry.slots[2] }
end

local function adminData(src)
    local list = core:GetWeaponCatalog()
    for _, weapon in ipairs(list) do weapon.owned = core:OwnsWeapon(src, weapon.id) end
    return list
end

exports('GetObtained', function(src)
    local entry = cache[src]
    local ids = {}
    if entry then for id in pairs(entry.obtained) do ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
end)

exports('GetEquipped', function(src)
    local entry = cache[src]
    if not entry then return {} end
    local result = {}
    for i = 1, 2 do
        local id = entry.slots[i]
        if id and core:OwnsWeapon(src, id) then result[#result + 1] = id end
    end
    return result
end)

local function preload(src)
    CreateThread(function()
        for _ = 1, 60 do
            if not GetPlayerName(src) then return end
            if ready() then
                withInventory(src, function() end)
                return
            end
            Wait(250)
        end
    end)
end

AddEventHandler('playerJoining', function() preload(source) end)
AddEventHandler('playerDropped', function()
    cache[source], busy[source], lastAction[source] = nil, nil, nil
end)
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do preload(tonumber(id)) end
end)

RegisterNetEvent('gf_inventory:requestLocker', function()
    local src = source
    withInventory(src, function(entry)
        TriggerClientEvent('gf_inventory:locker', src, lockerData(src, entry))
    end)
end)

RegisterNetEvent('gf_inventory:equip', function(slot, weaponId)
    local src = source
    if (slot ~= 1 and slot ~= 2) or type(weaponId) ~= 'string' or #weaponId > 48 then return end
    withInventory(src, function(entry)
        if not core:OwnsWeapon(src, weaponId) then return end
        local slots = core:ResolveSelection(src, entry.slots)
        local other = slot == 1 and 2 or 1
        if slots[other] == weaponId then slots[other] = slots[slot] end
        slots[slot] = weaponId
        MySQL.prepare.await('INSERT INTO gf_player_loadout (identifier, slot1, slot2) VALUES (?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE slot1 = VALUES(slot1), slot2 = VALUES(slot2)',
            { entry.id, slots[1], slots[2] })
        if not GetPlayerName(src) or identifierOf(src) ~= entry.id then return end
        entry.slots = slots
        TriggerClientEvent('gf_inventory:locker', src, lockerData(src, entry))
    end)
end)

RegisterCommand('armes', function(src)
    if src == 0 then return print('[gf_inventory] La commande /armes s’utilise en jeu.') end
    if not core:IsAdmin(src) then return core:Notify(src, 'Réservé aux administrateurs.') end
    withInventory(src, function()
        TriggerClientEvent('gf_inventory:openAdmin', src, adminData(src))
    end)
end, false)

RegisterNetEvent('gf_inventory:adminGive', function(weaponId)
    local src = source
    if type(weaponId) ~= 'string' or #weaponId > 48 or not core:IsAdmin(src) then return end
    withInventory(src, function(entry)
        if not core:IsAdmin(src) then return end
        local chosen
        for _, weapon in ipairs(core:GetWeaponCatalog()) do
            if weapon.id == weaponId then chosen = weapon break end
        end
        if not chosen then return end
        if not core:OwnsWeapon(src, weaponId) then
            MySQL.prepare.await('INSERT IGNORE INTO gf_player_weapons (identifier, weapon_id, origin) VALUES (?, ?, ?)',
                { entry.id, weaponId, 'admin' })
            if not GetPlayerName(src) or identifierOf(src) ~= entry.id then return end
            entry.obtained[weaponId] = true
        end
        core:Notify(src, ('%s ajoutée à ton Casier.'):format(chosen.label))
        TriggerClientEvent('gf_inventory:adminData', src, adminData(src))
    end)
end)
