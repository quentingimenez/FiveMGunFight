-- =============================================================================
--  gf_screen - CLIENT
--  Simple relais entre la page NUI et le réseau : capture côté joueur regardé,
--  visionneuse côté administrateur. Le serveur seul décide des deux directions.
--  Aucune native de focus : la page reste invisible et ne prend jamais le focus.
-- =============================================================================

local captureEnCours = false
local vueEnCours = false

local PREFIXES = { 'data:image/webp;base64,', 'data:image/jpeg;base64,' }

-- FiveM transmet le callback NUI comme référence de fonction : une table avec
-- un métaméthode __call, pas une fonction Lua. Tester seulement type(cb)
-- laissait chaque réponse sans effet.
local function estAppelable(valeur)
    if type(valeur) == 'function' then return true end
    local meta = getmetatable(valeur)
    return type(meta) == 'table' and rawget(meta, '__call') ~= nil
end

--- Un callback vient du viewport : s'il n'est pas appelable, FiveM l'ignore.
--- Ne pas lever d'erreur, ne pas répondre deux fois — y compris sur un refus.
local function repondre(cb, reponse)
    if not estAppelable(cb) then return end
    cb(reponse)
end

--- Un nombre doit être fini : NaN et infinis sont rejetés.
local function nombreFini(valeur)
    if type(valeur) ~= 'number' then return false end
    if valeur ~= valeur then return false end
    return valeur ~= math.huge and valeur ~= -math.huge
end

--- Longueur maximale d'une frame, telle que déclarée dans la configuration.
--- Sans valeur exploitable, aucun relais n'est autorisé.
local function limiteFrame()
    if type(Config) ~= 'table' then return nil end
    local max = Config.MaxFrameChars
    if not nombreFini(max) or max <= 0 then return nil end
    return max
end

--- Image webp ou jpeg embarquée : préfixe exact au début de la chaîne, puis
--- longueur bornée. Aucun assouplissement (ni recherche ailleurs, ni trim).
local function imageValide(image)
    if type(image) ~= 'string' then return false end
    local prefixeTrouve = false
    for _, prefixe in ipairs(PREFIXES) do
        if image:sub(1, #prefixe) == prefixe then
            prefixeTrouve = true
            break
        end
    end
    if not prefixeTrouve then return false end
    local max = limiteFrame()
    if max == nil then return false end
    return #image <= max
end

--- Bornes génériques pour les champs numériques du HUD.
local function borner(valeur, min, max)
    return math.max(min, math.min(max, valeur))
end

--- Noms d'armes du catalogue, en cache paresseux : un échec d'export n'est pas
--- bloquant et sera retenté à la frame suivante.
local nomsArmes = nil

local function chargerNomsArmes()
    if nomsArmes then return end
    local liste
    local ok = pcall(function()
        liste = exports.gf_core:GetWeaponThumbList()
    end)
    -- Échec d'export : ne pas figer un cache vide, réessayer à la frame suivante.
    if not ok or type(liste) ~= 'table' then return end
    local cache = {}
    for _, entree in pairs(liste) do
        if type(entree) == 'table' and type(entree.id) == 'string' and type(entree.label) == 'string' then
            local hash = joaat(entree.id)
            cache[hash] = entree.label
            cache[hash & 0xFFFFFFFF] = entree.label -- hash non signé aussi utilisé ailleurs
        end
    end
    -- Une liste vide légitime fige un cache vide (aucun retry nécessaire).
    nomsArmes = cache
end

--- Construit les métadonnées HUD jointes à l'image, avec les bornes du contrat.
local function construireMeta(ped, w, h)
    local hp = 0
    if not IsEntityDead(ped) then
        hp = math.floor((GetEntityHealth(ped) - 100) / math.max(GetEntityMaxHealth(ped) - 100, 1) * 100 + 0.5)
    end
    hp = borner(hp, 0, 100)

    local armour = borner(GetPedArmour(ped), 0, 100)

    local hash = GetSelectedPedWeapon(ped)
    local unarmed = joaat('WEAPON_UNARMED')
    local weapon = ''
    if hash ~= 0 and hash ~= unarmed and (hash & 0xFFFFFFFF) ~= (unarmed & 0xFFFFFFFF) then
        chargerNomsArmes()
        -- Export en échec : nomsArmes reste nil, valeur neutre sans indexer nil.
        if nomsArmes then
            weapon = nomsArmes[hash] or nomsArmes[hash & 0xFFFFFFFF] or '?'
        else
            weapon = '?'
        end
        if #weapon > 32 then weapon = weapon:sub(1, 32) end
    end

    local clip = GetAmmoInClip(ped, hash)
    if not nombreFini(clip) then clip = select(2, GetAmmoInClip(ped, hash)) end
    if not nombreFini(clip) then clip = 0 end
    clip = borner(clip, 0, 9999)
    local ammo = GetAmmoInPedWeapon(ped, hash)
    if not nombreFini(ammo) then ammo = 0 end
    ammo = borner(ammo, 0, 9999)

    local mode = LocalPlayer.state.gf_mode or ''
    if type(mode) ~= 'string' then mode = '' end
    if #mode > 16 then mode = mode:sub(1, 16) end

    local veh = GetVehiclePedIsIn(ped, false)
    local vehicle = veh ~= 0
    local speed = GetEntitySpeed(vehicle and veh or ped) * 3.6
    if not nombreFini(speed) then speed = 0 end
    speed = borner(speed, 0, 999)

    return {
        hp = hp, armour = armour, weapon = weapon, clip = clip, ammo = ammo,
        mode = mode, vehicle = vehicle, speed = speed, w = w, h = h,
    }
end

-- ------------------------------------------------------------------ NUI → client

RegisterNUICallback('ready', function(_, cb)
    repondre(cb, { ok = true })
end)

-- Seule porte de sortie des images produites par la page. Hors capture, rien
-- ne doit monter au serveur : une frame en vol après un arrêt est écartée.
RegisterNUICallback('frame', function(data, cb)
    if not captureEnCours then
        repondre(cb, { ok = false })
        return
    end
    if type(data) ~= 'table' or not imageValide(data.data) then
        repondre(cb, { ok = false })
        return
    end

    local ped = PlayerPedId()
    local meta = construireMeta(ped, data.w, data.h)
    TriggerLatentServerEvent('gf_screen:frame', Config.UploadBps, { image = data.data, meta = meta })
    repondre(cb, { ok = true })
end)

-- ------------------------------------------------------------ serveur → client

-- Réglages strictement validés : la page ne reçoit que des valeurs sûres.
RegisterNetEvent('gf_screen:captureStart', function(d)
    if type(d) ~= 'table' then return end
    if not nombreFini(d.fps) or d.fps < 1 or d.fps > 30 or d.fps % 1 ~= 0 then return end
    if not nombreFini(d.width) or d.width % 1 ~= 0 or d.width < 320 or d.width > 1920 then return end
    if not nombreFini(d.quality) or d.quality < 0 or d.quality > 1 then return end

    local format = type(d.format) == 'string' and d.format or 'webp'
    captureEnCours = true
    SendNUIMessage({
        type = 'captureStart',
        fps = d.fps,
        width = d.width,
        quality = d.quality,
        format = format,
    })
end)

RegisterNetEvent('gf_screen:captureStop', function()
    captureEnCours = false
    SendNUIMessage({ type = 'captureStop' })
end)

RegisterNetEvent('gf_screen:viewStart', function(d)
    if type(d) ~= 'table' then return end
    if type(d.name) ~= 'string' or #d.name > 64 then return end
    if type(d.preset) ~= 'string' then return end

    vueEnCours = true
    SendNUIMessage({ type = 'viewStart', name = d.name, preset = d.preset })
end)

RegisterNetEvent('gf_screen:viewStop', function()
    vueEnCours = false
    SendNUIMessage({ type = 'viewStop' })
end)

RegisterNetEvent('gf_screen:frame', function(d)
    if type(d) ~= 'table' or not imageValide(d.image) then return end
    SendNUIMessage({ type = 'frame', data = d.image, meta = d.meta, preset = d.preset })
end)

-- -------------------------------------------------------------- Fin de ressource

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    -- Arrêt purement local : aucun événement serveur, aucune native de focus.
    if captureEnCours then
        captureEnCours = false
        SendNUIMessage({ type = 'captureStop' })
    end
    if vueEnCours then
        vueEnCours = false
        SendNUIMessage({ type = 'viewStop' })
    end
end)
