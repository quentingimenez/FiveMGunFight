-- =============================================================================
--  gf_thumbs - SERVEUR
--  Stocke les photos (thumbs/<famille>/<id>.png + thumbs/index.json) et les
--  envoie aux clients en data URL, à la demande.
--
--  Commande admin : /thumbs <famille> [id]  -> le client de l'admin prend les photos
--  Événements client -> serveur :
--    gf_thumbs:save    (admin) une photo prise par le studio
--    gf_thumbs:request (tous)  demande les photos d'une famille
-- =============================================================================

local RES = GetCurrentResourceName()
local core = exports.gf_core
local INDEX = Config.Folder .. '/index.json'
local PNG_PREFIX = 'data:image/png;base64,'
local PNG_MAGIC = '\137PNG\r\n\26\n'

local Index = {}       -- [famille] = { [id] = version }
local Cache = {}       -- [famille] = { [id] = dataURL }
local lastRequest = {} -- [src] = GetGameTimer()

local function validId(id)
    return type(id) == 'string' and #id >= 1 and #id <= 64 and id:match('^[%w_]+$') ~= nil
end

local function loadIndex()
    local raw = LoadResourceFile(RES, INDEX)
    local ok, data = pcall(json.decode, raw or '')
    Index = {}
    if ok and type(data) == 'table' then
        for kind, ids in pairs(data) do
            if Config.Kinds[kind] and type(ids) == 'table' then
                Index[kind] = {}
                for id, v in pairs(ids) do
                    if validId(id) then Index[kind][id] = tonumber(v) or 1 end
                end
            end
        end
    end
end

local function photoPath(kind, id)
    return ('%s/%s/%s.png'):format(Config.Folder, kind, id)
end

local function dataURL(kind, id)
    Cache[kind] = Cache[kind] or {}
    if Cache[kind][id] then return Cache[kind][id] end
    local raw = LoadResourceFile(RES, photoPath(kind, id))
    if not raw or raw:sub(1, 8) ~= PNG_MAGIC then return nil end
    local url = PNG_PREFIX .. Base64.encode(raw)
    Cache[kind][id] = url
    return url
end

loadIndex()

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
    Index[kind] = Index[kind] or {}
    Index[kind][id] = (Index[kind][id] or 0) + 1
    SaveResourceFile(RES, INDEX, json.encode(Index), -1)
    if Cache[kind] then Cache[kind][id] = nil end
    TriggerClientEvent('gf_thumbs:updated', -1, kind, id)
    print(('[gf_thumbs] Photo %s/%s enregistrée (%d Ko)'):format(kind, id, math.ceil(#raw / 1024)))
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
        if validId(id) and Index[kind] and Index[kind][id] then
            result[id] = dataURL(kind, id)
        end
    end
    -- Envoi « latent » : étalé dans le temps pour ne pas saturer la connexion
    TriggerLatentClientEvent('gf_thumbs:data', src, 512 * 1024, reqId, kind, result)
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)
