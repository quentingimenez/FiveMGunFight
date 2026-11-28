-- =============================================================================
--  gf_killcam - SERVEUR
--  Réception des échantillons, horodatage, construction et envoi des clips.
--  Aucun identifiant (license, ip, ...) n'est jamais inclus dans un clip.
-- =============================================================================

-- Tampons par joueur : liste d'échantillons horodatés (horloge serveur).
local Tampons = {}
-- Dernier lot accepté par joueur (horloge serveur), pour le rate-limit.
local DernierLot = {}
-- Fin du clip en cours par victime (horloge serveur).
local Restants = {}

-- ---------------------------------------------------------------- Utilitaires

-- Entier (nombre sans partie fractionnaire), utilisé pour les ids de joueurs.
local function estEntier(n)
    return math.tointeger(n) ~= nil
end

-- Mode courant d'un joueur, sous pcall : une ressource absente ne doit jamais
-- interrompre le handler. Retourne nil si le mode n'est pas lisible.
local function modeJoueur(src)
    local ok, mode = pcall(function() return exports.gf_core:GetMode(src) end)
    if ok and type(mode) == 'string' then return mode end
    return nil
end

-- Dernier échantillon d'un tampon (ou nil si le tampon est vide).
local function dernier(tampon)
    if not tampon or #tampon == 0 then return nil end
    return tampon[#tampon]
end

-- Distance 3D entre deux échantillons (positions du ped).
local function distance3d(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ---------------------------------------------------------------- Réception

RegisterNetEvent('gf_killcam:samples', function(lot)
    local src = source

    -- Le mode est relu à chaque lot : un joueur peut changer de mode à tout moment.
    local ok, mode = pcall(function() return exports.gf_core:GetMode(src) end)
    if not (ok and type(mode) == 'string' and Config.Modes[mode] == true) then return end

    -- Rate-limit strict : un lot par 700 ms. Un lot trop tôt est refusé sans
    -- repousser l'échéance, afin qu'un envoi à >= 700 ms soit accepté.
    local maintenant = GetGameTimer()
    local precedent = DernierLot[src]
    if precedent and maintenant - precedent < 700 then return end
    DernierLot[src] = maintenant

    local propre = GFKillcamTrack.clean(lot)
    if not propre or #propre == 0 then return end

    -- Horodatage serveur : le dernier échantillon vaut maintenant, les
    -- précédents sont espacés de SampleMs. Les valeurs de Config sont relues
    -- à chaque appel pour rester testables.
    local sampleMs = Config.SampleMs
    for i = 1, #propre do
        propre[i].t = maintenant - (#propre - i) * sampleMs
    end

    local tampon = Tampons[src]
    if not tampon then
        tampon = {}
        Tampons[src] = tampon
    end
    for i = 1, #propre do
        tampon[#tampon + 1] = propre[i]
    end

    -- Bornage du tampon à BufferSeconds.
    local limite = maintenant - Config.BufferSeconds * 1000
    while #tampon > 0 and tampon[1].t < limite do
        table.remove(tampon, 1)
    end
end)

-- ---------------------------------------------------------------- Clip

AddEventHandler('gf:playerKilled', function(victime, tueur, arme, mode)
    if not Config.Enabled then return end
    if type(mode) ~= 'string' or Config.Modes[mode] ~= true then return end
    if not estEntier(tueur) then return end
    if GetPlayerName(tueur) == nil then return end
    if tueur == victime then return end

    local tamponTueur = Tampons[tueur]
    if not tamponTueur or #tamponTueur == 0 then return end

    local maintenant = GetGameTimer()
    local secondes = math.max(3, math.min(30, Config.ReplaySeconds))

    local clip = {
        killer = {
            id = tueur,
            name = GetPlayerName(tueur),
            samples = GFKillcamTrack.slice(tamponTueur, maintenant, secondes),
        },
        victim = { id = victime, name = GetPlayerName(victime) or '?', samples = {} },
        others = {},
        weapon = estEntier(arme) and arme or 0,
        duration = secondes,
    }

    -- Le tampon peut être non vide mais ne contenir aucun échantillon dans la
    -- fenêtre de rejeu : inutile d'envoyer un clip vide ni de lancer Restants.
    if not clip.killer.samples or #clip.killer.samples == 0 then return end

    local tamponVictime = Tampons[victime]
    if tamponVictime and #tamponVictime > 0 then
        clip.victim.samples = GFKillcamTrack.slice(tamponVictime, maintenant, secondes)
    end

    -- Voisins du tueur : même mode, proches dans l'espace, ids triés et limités.
    local reference = dernier(tamponTueur)
    local rayon = Config.OthersRadius
    local candidats = {}
    for _, idStr in ipairs(GetPlayers()) do
        local id = tonumber(idStr)
        if id and id ~= tueur and id ~= victime and estEntier(id) then
            local tampon = Tampons[id]
            local dernierSample = dernier(tampon)
            if dernierSample and reference and modeJoueur(id) == mode
                and distance3d(dernierSample, reference) <= rayon then
                candidats[#candidats + 1] = id
            end
        end
    end
    table.sort(candidats)

    local maxOthers = Config.MaxOthers
    for i = 1, math.min(maxOthers, #candidats) do
        local id = candidats[i]
        local samples = GFKillcamTrack.slice(Tampons[id], maintenant, secondes)
        if samples and #samples > 0 then
            clip.others[#clip.others + 1] = {
                id = id,
                name = GetPlayerName(id) or '?',
                samples = samples,
            }
        end
    end

    TriggerLatentClientEvent('gf_killcam:play', victime, 250000, clip)
    Restants[victime] = maintenant + secondes * 1000
end)

-- ---------------------------------------------------------------- Export

exports('RemainingMs', function(victime)
    local echeance = Restants[victime]
    if not echeance then return 0 end
    local reste = echeance - GetGameTimer()
    if reste <= 0 then return 0 end
    return math.floor(reste)
end)

-- ---------------------------------------------------------------- Nettoyage

AddEventHandler('playerDropped', function()
    local src = source
    Tampons[src] = nil
    DernierLot[src] = nil
    Restants[src] = nil
end)

AddEventHandler('gf:modeLeft', function(src)
    Tampons[src] = nil
    DernierLot[src] = nil
    -- Restants est volontairement conservé : le clip déjà envoyé doit finir.
end)
