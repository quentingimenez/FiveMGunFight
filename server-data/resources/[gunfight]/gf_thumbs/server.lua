-- =============================================================================
--  gf_thumbs - SERVEUR
--  Stocke les photos (thumbs/<famille>/<id>.png) et les envoie aux clients en
--  data URL, à la demande. Pas d'index : le serveur lit directement le fichier,
--  ce qui reste juste quand le volume de production mélange les photos de
--  l'image et celles prises en jeu.
--
--  Commande admin : /thumbs <famille> [id]  -> le client de l'admin prend les photos
--  Événements client -> serveur :
--    gf_thumbs:save    (admin) une photo prise par le studio
--    gf_thumbs:request (tous)  demande les photos d'une famille
--    gf_thumbs:lobbyReady (tous) arrivée au lobby ; si admin -> photos manquantes
-- =============================================================================

local RES = GetCurrentResourceName()
local core = exports.gf_core
local PNG_PREFIX = 'data:image/png;base64,'
local PNG_MAGIC = '\137PNG\r\n\26\n'

local Cache = {}       -- [famille] = { [id] = dataURL | false (pas de photo) }
local lastRequest = {} -- [src] = GetGameTimer()

local function validId(id)
    return type(id) == 'string' and #id >= 1 and #id <= 64 and id:match('^[%w_]+$') ~= nil
end

local function photoPath(kind, id)
    return ('%s/%s/%s.png'):format(Config.Folder, kind, id)
end

local function dataURL(kind, id)
    Cache[kind] = Cache[kind] or {}
    local cached = Cache[kind][id]
    if cached ~= nil then return cached or nil end
    local raw = LoadResourceFile(RES, photoPath(kind, id))
    if not raw or raw:sub(1, 8) ~= PNG_MAGIC then
        Cache[kind][id] = false
        return nil
    end
    local url = PNG_PREFIX .. Base64.encode(raw)
    Cache[kind][id] = url
    return url
end

-- ---------------------------------------------------------------- Prise de photos
RegisterCommand('thumbs', function(src, args)
    if src == 0 then return print('[gf_thumbs] La commande /thumbs s\'utilise en jeu.') end
    if not core:IsAdmin(src) then return core:Notify(src, 'Réservé aux administrateurs.') end
    local kind, id = args[1], args[2]
    if not Config.Kinds[kind] then
        local names = {}
        for k in pairs(Config.Kinds) do names[#names + 1] = k end
        table.sort(names)
        return core:Notify(src, 'Usage : /thumbs <' .. table.concat(names, '|') .. '> [id]')
    end
    if id ~= nil and not validId(id) then return core:Notify(src, 'Identifiant invalide.') end
    TriggerClientEvent('gf_thumbs:capture', src, kind, id)
end, false)

RegisterNetEvent('gf_thumbs:save', function(kind, id, url)
    local src = source
    if not core:IsAdmin(src) then return end
    if not Config.Kinds[kind] or not validId(id) then return end
    if type(url) ~= 'string' or url:sub(1, #PNG_PREFIX) ~= PNG_PREFIX then return end
    local raw = Base64.decode(url:sub(#PNG_PREFIX + 1))
    if not raw or #raw > Config.MaxImageBytes or raw:sub(1, 8) ~= PNG_MAGIC then return end

    if not SaveResourceFile(RES, photoPath(kind, id), raw, #raw) then
        print(('^1[gf_thumbs] Impossible d\'écrire %s (dossier %s/%s manquant ?)^0'):format(photoPath(kind, id), Config.Folder, kind))
        return core:Notify(src, ('Photo %s/%s non enregistrée (voir la console serveur).'):format(kind, id))
    end
    if Cache[kind] then Cache[kind][id] = nil end
    TriggerClientEvent('gf_thumbs:updated', -1, kind, id)
    print(('[gf_thumbs] Photo %s/%s enregistrée (%d Ko)'):format(kind, id, math.ceil(#raw / 1024)))
end)

-- Arrivée d'un joueur au lobby : si c'est un admin, son jeu prend les photos
-- manquantes. Une limite évite les demandes répétées d'un client.
local lastAuto = {}
RegisterNetEvent('gf_thumbs:lobbyReady', function()
    local src = source
    if not Config.AutoCapture then return end
    if not core:IsAdmin(src) then return end
    local now = GetGameTimer()
    if lastAuto[src] and now - lastAuto[src] < 3000 then return end
    lastAuto[src] = now
    TriggerClientEvent('gf_thumbs:autoCapture', src)
end)

-- ---------------------------------------------------------------- Distribution
RegisterNetEvent('gf_thumbs:request', function(reqId, kind, ids)
    local src = source
    if type(reqId) ~= 'number' or not Config.Kinds[kind] or type(ids) ~= 'table' then return end
    local now = GetGameTimer()
    if lastRequest[src] and now - lastRequest[src] < 250 then return end
    lastRequest[src] = now

    local result = {}
    local count = 0
    for _, id in ipairs(ids) do
        count = count + 1
        if count > 100 then break end
        if validId(id) then result[id] = dataURL(kind, id) end
    end
    -- Envoi « latent » : étalé dans le temps pour ne pas saturer la connexion
    TriggerLatentClientEvent('gf_thumbs:data', src, 512 * 1024, reqId, kind, result)
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
    lastAuto[source] = nil
end)

-- Un client signale qu'un modèle l'a fait planter pendant sa photo (marqueur KVP
-- resté posé). Simple alerte dans la console : le modèle est sans doute corrompu
-- et doit être retiré (voir docs/ajouter-un-modele.md, « Dépannage »).
local brokenSeen = {}
RegisterNetEvent('gf_thumbs:broken', function(ref)
    local src = source
    if brokenSeen[src] or type(ref) ~= 'string' or #ref > 80 or not ref:match('^[%w_]+/[%w_]+$') then return end
    brokenSeen[src] = true
    print(('^1[gf_thumbs] %s : le modèle %s a fait planter son jeu pendant la photo (modèle corrompu ?)^0')
        :format(GetPlayerName(src) or src, ref))
end)
AddEventHandler('playerDropped', function() brokenSeen[source] = nil end)
