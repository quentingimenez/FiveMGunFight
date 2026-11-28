-- =============================================================================
--  gf_screen - CLIENT
--  Simple relais entre la page NUI et le réseau : capture côté joueur regardé,
--  visionneuse côté administrateur. Le serveur seul décide des deux directions.
--  Aucune native de focus : la page reste invisible et ne prend jamais le focus.
-- =============================================================================

local captureEnCours = false
local vueEnCours = false

local PREFIXE = 'data:image/jpeg;base64,'

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

--- Image JPEG embarquée : préfixe exact au début de la chaîne, puis longueur
--- bornée. Aucun assouplissement (ni recherche du préfixe ailleurs, ni trim).
local function imageValide(image)
    if type(image) ~= 'string' then return false end
    if image:sub(1, #PREFIXE) ~= PREFIXE then return false end
    local max = limiteFrame()
    if max == nil then return false end
    return #image <= max
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
    if type(data) ~= 'table' or type(data.data) ~= 'string' then
        repondre(cb, { ok = false })
        return
    end
    if not imageValide(data.data) then
        repondre(cb, { ok = false })
        return
    end

    TriggerLatentServerEvent('gf_screen:frame', 300000, data.data)
    repondre(cb, { ok = true })
end)

-- ------------------------------------------------------------ serveur → client

-- Réglages strictement validés : la page ne reçoit que des valeurs sûres.
RegisterNetEvent('gf_screen:captureStart', function(d)
    if type(d) ~= 'table' then return end
    if not nombreFini(d.fps) or d.fps < 1 or d.fps > 5 then return end
    if not nombreFini(d.width) or d.width % 1 ~= 0 or d.width <= 0 then return end
    if not nombreFini(d.quality) or d.quality < 0 or d.quality > 1 then return end

    captureEnCours = true
    SendNUIMessage({
        type = 'captureStart',
        fps = d.fps,
        width = d.width,
        quality = d.quality,
    })
end)

RegisterNetEvent('gf_screen:captureStop', function()
    captureEnCours = false
    SendNUIMessage({ type = 'captureStop' })
end)

RegisterNetEvent('gf_screen:viewStart', function(d)
    if type(d) ~= 'table' then return end
    if type(d.name) ~= 'string' or #d.name > 64 then return end

    vueEnCours = true
    SendNUIMessage({ type = 'viewStart', name = d.name })
end)

RegisterNetEvent('gf_screen:viewStop', function()
    vueEnCours = false
    SendNUIMessage({ type = 'viewStop' })
end)

RegisterNetEvent('gf_screen:frame', function(image)
    if not imageValide(image) then return end
    SendNUIMessage({ type = 'frame', data = image })
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
