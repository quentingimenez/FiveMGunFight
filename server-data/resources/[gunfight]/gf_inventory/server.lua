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
    local accessories = MySQL.query.await('SELECT weapon_id, selections FROM gf_weapon_accessories WHERE identifier = ?', { id })
    if not GetPlayerName(src) or identifierOf(src) ~= id then return nil end
    local entry = { id = id, obtained = {}, slots = {}, accessories = {} }
    for _, row in ipairs(rows or {}) do entry.obtained[row.weapon_id] = true end
    if selection then entry.slots = { selection.slot1, selection.slot2 } end
    for _, row in ipairs(accessories or {}) do
        local ok, decoded = pcall(json.decode, row.selections or '')
        if ok and type(decoded) == 'table' then entry.accessories[row.weapon_id] = decoded end
    end
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
    local weapons = core:GetOwnedWeapons(src)
    for _, weapon in ipairs(weapons) do
        weapon.accessories = WeaponAccessories.catalog(weapon.name)
        weapon.selections = WeaponAccessories.validate(weapon.accessories, entry.accessories[weapon.id] or {}) or {}
    end
    return { weapons = weapons, slot1 = entry.slots[1], slot2 = entry.slots[2] }
end

exports('GetWeaponAccessories', function(src, weaponId, weaponName)
    local entry = cache[src]
    if not entry then return {}, {} end
    local catalog = WeaponAccessories.catalog(weaponName)
    local selected = WeaponAccessories.validate(catalog, entry.accessories[weaponId] or {}) or {}
    local remove, add = {}, {}
    for kind, group in pairs(catalog) do
        local value = selected[kind]
        if value == nil and group.applyDefault then value = group.default end
        if value ~= nil then
            for _, option in ipairs(group.options) do remove[#remove + 1] = option end
            if value ~= '' then add[#add + 1] = value end
        end
    end
    return remove, add
end)

local function adminData(src)
    local list = core:GetWeaponCatalog()
    for _, weapon in ipairs(list) do weapon.owned = core:OwnsWeapon(src, weapon.id) end
    return list
end

local function grantWeapon(target, weaponId)
    if type(weaponId) ~= 'string' or #weaponId < 1 or #weaponId > 48 then return false, 'unknown' end
    local chosen
    for _, weapon in ipairs(core:GetWeaponCatalog()) do
        if weapon.id == weaponId then chosen = weapon break end
    end
    if not chosen then return false, 'unknown' end
    if not GetPlayerName(target) then return false, 'offline' end
    local entry = load(target)
    if not entry then return false, 'unavailable' end
    if core:OwnsWeapon(target, weaponId) then return true, 'already', chosen end
    MySQL.prepare.await('INSERT IGNORE INTO gf_player_weapons (identifier, weapon_id, origin) VALUES (?, ?, ?)',
        { entry.id, weaponId, 'admin' })
    if not GetPlayerName(target) or identifierOf(target) ~= entry.id then return false, 'offline' end
    entry.obtained[weaponId] = true
    return true, 'granted', chosen
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
        if core:GetMode(src) == 'redzone' then
            local canChange = GetResourceState('gf_redzone') == 'started'
                and exports.gf_redzone:CanChangeWeapons(src)
            if not canChange then
                core:Notify(src, 'Sors de la zone de combat pour changer d’arme.')
                TriggerClientEvent('gf_inventory:locker', src, lockerData(src, entry))
                return
            end
        end
        local slots = core:ResolveSelection(src, entry.slots)
        local other = slot == 1 and 2 or 1
        if slots[other] == weaponId then slots[other] = slots[slot] end
        slots[slot] = weaponId
        MySQL.prepare.await('INSERT INTO gf_player_loadout (identifier, slot1, slot2) VALUES (?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE slot1 = VALUES(slot1), slot2 = VALUES(slot2)',
            { entry.id, slots[1], slots[2] })
        if not GetPlayerName(src) or identifierOf(src) ~= entry.id then return end
        entry.slots = slots
        TriggerEvent('gf_inventory:selectionChanged', src)
        TriggerClientEvent('gf_inventory:locker', src, lockerData(src, entry))
    end)
end)

RegisterNetEvent('gf_inventory:setAccessories', function(weaponId, choices)
    local src = source
    if type(weaponId) ~= 'string' or #weaponId > 48 then return end
    withInventory(src, function(entry)
        if not core:OwnsWeapon(src, weaponId) then return end
        if core:GetMode(src) == 'redzone' and (GetResourceState('gf_redzone') ~= 'started'
            or not exports.gf_redzone:CanChangeWeapons(src)) then
            core:Notify(src, 'Sors de la zone de combat pour modifier tes accessoires.')
            TriggerClientEvent('gf_inventory:locker', src, lockerData(src, entry))
            return
        end
        local weapon
        for _, item in ipairs(core:GetOwnedWeapons(src)) do if item.id == weaponId then weapon = item break end end
        if not weapon then return end
        local selected = WeaponAccessories.validate(WeaponAccessories.catalog(weapon.name), choices)
        if not selected then return end
        MySQL.prepare.await('INSERT INTO gf_weapon_accessories (identifier, weapon_id, selections) VALUES (?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE selections = VALUES(selections)', { entry.id, weaponId, json.encode(selected) })
        if not GetPlayerName(src) or identifierOf(src) ~= entry.id then return end
        entry.accessories[weaponId] = selected
        TriggerEvent('gf_inventory:selectionChanged', src)
        core:Notify(src, 'Accessoires enregistrés.')
        TriggerClientEvent('gf_inventory:locker', src, lockerData(src, entry))
        TriggerClientEvent('gf_inventory:accessoriesSaved', src, weaponId)
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
    withInventory(src, function()
        if not core:IsAdmin(src) then return end
        local ok, status, chosen = grantWeapon(src, weaponId)
        if not ok or (status ~= 'granted' and status ~= 'already') then return end
        core:Notify(src, ('%s ajoutée à ton Casier.'):format(chosen.label))
        TriggerClientEvent('gf_inventory:adminData', src, adminData(src))
    end)
end)

-- Pas de contrôle admin ici : cet export serveur est appelé par des ressources de confiance.
exports('GiveWeaponToLocker', function(target, weaponId)
    local ok, result, status = pcall(grantWeapon, target, weaponId)
    if not ok then
        print(('[gf_inventory] %s'):format(tostring(result)))
        return false, 'error'
    end
    return result, status
end)

RegisterCommand('give', function(src, args)
    local function reply(msg)
        if src == 0 then print('[gf_inventory] ' .. msg) else core:Notify(src, msg) end
    end
    if src ~= 0 and not core:IsAdmin(src) then
        reply('Réservé aux administrateurs.')
        return
    end
    local target = tonumber(args[1])
    local weaponId = args[2] and args[2]:lower()
    if not target or not weaponId then
        reply('Usage : give <id joueur> <arme> (ex. give 12 carbine).')
        return
    end
    local ok, result, status, chosen = pcall(grantWeapon, target, weaponId)
    if not ok then
        print(('[gf_inventory] %s'):format(tostring(result)))
        reply('Inventaire indisponible. Réessaie dans un instant.')
        return
    end
    if status == 'unknown' then
        reply(('Arme inconnue : %s (identifiant du catalogue, ex. carbine).'):format(weaponId))
        return
    end
    if status == 'offline' then
        reply(('Joueur %s introuvable.'):format(args[1]))
        return
    end
    if status == 'unavailable' then
        reply('Inventaire indisponible. Réessaie dans un instant.')
        return
    end
    local nom = GetPlayerName(target)
    if status == 'already' then
        reply(('%s possède déjà %s.'):format(nom, chosen.label))
        return
    end
    reply(('%s ajoutée au Casier de %s.'):format(chosen.label, nom))
    core:Notify(target, ('%s ajoutée à ton Casier par un administrateur.'):format(chosen.label))
    local auteur = src == 0 and 'console' or GetPlayerName(src)
    print(('[gf_inventory] %s a donné %s à %s'):format(auteur, weaponId, nom))
end, false)
