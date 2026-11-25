-- =============================================================================
--  gf_lobby - SERVEUR
--  Autorité du lobby : escouades, invitations, sélection de mode et lancement.
--  Le client ne fournit jamais d'identifiant d'escouade : tout part de `source`.
-- =============================================================================

local RESOURCE = GetCurrentResourceName()
local ADMIN_ACE = 'gunfight.admin'

local Players = {}   -- [src] = { identifier, character, partyId, inLobby, ... }
local Parties = {}   -- [id]  = { id, leader, members = {src...}, selectedMode, launching }
local Invites = {}   -- [src] = { partyId, from, expiresAt }
local Store = {}     -- [identifier] = character
local nextPartyId = 1

-- File de recherche serveur globale. Une seule recherche active à la fois :
-- tous les joueurs du lobby avec un personnage sont éligibles/auto-inscrits.
local Queue = {
  active = false,
  mode = nil,
  owner = nil,     -- src du chef qui a lancé la recherche (annulation)
  members = {},    -- [src] = true
}


local function log(message)
    print(('[gf_lobby] %s'):format(tostring(message)))
end

-- Version du build déployé : la convar gf_build_sha est posée par
-- docker/entrypoint.sh depuis l'argument BUILD_SHA de l'image Docker (sha court
-- du commit construit). Hors conteneur, elle est absente et on affiche « dev ».
-- La valeur est filtrée : elle finit dans l'interface du lobby.
local function buildSha()
    local sha = tostring(GetConvar('gf_build_sha', '') or ''):gsub('%s+', '')
    if not sha:match('^[%w._-]+$') then return 'dev' end
    return sha
end

local function playerName(src)
    return GetPlayerName(src) or ('Joueur %d'):format(src)
end

local function findIdentifier(src)
    local identifiers = GetPlayerIdentifiers(src) or {}
    for _, identifier in ipairs(identifiers) do
        if identifier:sub(1, 8) == 'license:' then
            return identifier, true
        end
    end
    for _, identifier in ipairs(identifiers) do
        if identifier:sub(1, 6) == 'fivem:'
            or identifier:sub(1, 8) == 'discord:'
            or identifier:sub(1, 6) == 'steam:' then
            return identifier, true
        end
    end
    return ('session:%d'):format(src), false
end

local function normalizeName(value)
    if type(value) ~= 'string' then return '' end
    local name = value:gsub('%c', ' ')
    name = name:gsub('%s+', ' ')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    return name
end

local function nameLength(name)
    local length = utf8.len(name)
    return length
end

local function normalizeCharacter(raw)
    if type(raw) ~= 'table' then return nil end

    local name = normalizeName(raw.name)
    local length = nameLength(name)
    if not length or length < Config.Character.nameMin or length > Config.Character.nameMax then
        return nil
    end

    local gender = raw.gender
    if gender ~= 'male' and gender ~= 'female' then return nil end

    local seed = tonumber(raw.seed)
    if not seed or seed ~= seed or seed == math.huge or seed == -math.huge then return nil end
    seed = math.floor(seed)
    if seed < 1 or seed > 2147483647 then return nil end

    local skin = tonumber(raw.skin)
    if not skin or skin ~= skin then return nil end
    skin = math.floor(skin)
    if skin < 0 then skin = 0 end
    if skin > Config.Character.skins - 1 then skin = Config.Character.skins - 1 end

    local createdAt = tonumber(raw.createdAt) or os.time()
    return {
        name = name,
        gender = gender,
        seed = seed,
        skin = skin,
        createdAt = math.floor(createdAt),
    }
end

local function loadCharacters()
    local raw = LoadResourceFile(RESOURCE, Config.CharacterStorage)
    if not raw or raw == '' then
        log('Aucun personnage enregistré.')
        return
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        log('Fichier de personnages illisible, aucun personnage chargé.')
        return
    end

    local characters = decoded.characters or decoded
    if type(characters) ~= 'table' then
        log('Fichier de personnages invalide, aucun personnage chargé.')
        return
    end

    local count = 0
    for identifier, rawCharacter in pairs(characters) do
        if type(identifier) == 'string' then
            local character = normalizeCharacter(rawCharacter)
            if character then
                Store[identifier] = character
                count = count + 1
            end
        end
    end
    log(('%d personnage(s) chargé(s).'):format(count))
end

local function saveCharacters()
    local payload = json.encode({ version = 1, characters = Store })
    local ok = SaveResourceFile(RESOURCE, Config.CharacterStorage, payload, -1)
    if not ok then
        log('Échec de sauvegarde de ' .. Config.CharacterStorage)
    end
end

local function notify(src, message, level)
    if not src or not message then return end
    TriggerClientEvent('gf_lobby:notice', src, {
        message = message,
        level = level or 'info',
    })
end

local function ensurePlayer(src)
    local player = Players[src]
    if player then return player end

    local identifier, persistent = findIdentifier(src)
    player = {
        identifier = identifier,
        persistent = persistent,
        character = Store[identifier],
        partyId = nil,
        inLobby = false,
        lastInvite = 0,
        lastMode = 0,
        lastPlayers = 0,
        lastState = 0,
        lastCreate = 0,
    }
    Players[src] = player
    return player
end

local function displayNameOf(src)
    local player = Players[src]
    if player and player.character and player.character.name then
        return player.character.name
    end
    return playerName(src)
end

local function findParty(src)
    local player = Players[src]
    if not player or not player.partyId then return nil end
    local party = Parties[player.partyId]
    if not party then
        player.partyId = nil
        return nil
    end
    for _, member in ipairs(party.members) do
        if member == src then return party end
    end
    player.partyId = nil
    return nil
end

local function isModeAvailable(mode)
    if not mode or mode.placeholder then return false end
    if mode.resource and GetResourceState(mode.resource) ~= 'started' then return false end
    return true
end

local function findMode(modeId)
    if type(modeId) ~= 'string' then return nil end
    for _, mode in ipairs(Config.Modes) do
        if mode.id == modeId then return mode end
    end
    return nil
end

local function defaultModeId()
    local preferred = findMode(Config.DefaultMode)
    if isModeAvailable(preferred) then return preferred.id end
    for _, mode in ipairs(Config.Modes) do
        if isModeAvailable(mode) then return mode.id end
    end
    return Config.DefaultMode
end

local function countModePlayers(mode)
    if not isModeAvailable(mode) then return 0 end
    local ok, list = pcall(function()
        return exports.gf_core:GetPlayersInMode(mode.id)
    end)
    if ok and type(list) == 'table' then return #list end
    return 0
end

local function modesForState()
    local modes = {}
    for _, mode in ipairs(Config.Modes) do
        modes[#modes + 1] = {
            id = mode.id,
            label = mode.label,
            short = mode.short,
            description = mode.description,
            icon = mode.icon,
            players = countModePlayers(mode),
            minPlayers = mode.minPlayers or 1,
            available = isModeAvailable(mode),
            placeholder = mode.placeholder == true,
        }
    end
    return modes
end

local function setBucket(src, partyId)
    local player = Players[src]
    if not player or not player.inLobby then return end
    pcall(SetPlayerRoutingBucket, src, Config.BucketBase + partyId)
end

-- Déclaration anticipée : buildState est défini avant les helpers de file.
local queueState

local function buildState(src)
    local player = Players[src]
    if not player then return nil end

    local party = findParty(src)
    local members = {}
    local memberIds = party and party.members or { src }
    for _, member in ipairs(memberIds) do
        local memberPlayer = Players[member]
        if memberPlayer and memberPlayer.inLobby then
            members[#members + 1] = {
                id = member,
                name = playerName(member),
                displayName = displayNameOf(member),
                slot = #members + 1,
                isLeader = not party or member == party.leader,
                isSelf = member == src,
                inLobby = true,
                character = memberPlayer.character,
            }
        end
    end

    return {
        serverName = Config.ServerName,
        build = buildSha(),
        online = #GetPlayers(),
        limits = {
            partyMax = Config.Party.maxSize,
            nameMin = Config.Character.nameMin,
            nameMax = Config.Character.nameMax,
            skins = Config.Character.skins,
        },
        me = {
            id = src,
            name = playerName(src),
            character = player.character,
            isLeader = not party or party.leader == src,
            inLobby = player.inLobby,
        },
        party = party and {
            id = party.id,
            leaderId = party.leader,
            leaderName = displayNameOf(party.leader),
            maxSize = Config.Party.maxSize,
            size = #members,
            selectedMode = party.selectedMode,
            launching = party.launching == true,
            members = members,
        } or {
            id = 0,
            leaderId = src,
            leaderName = displayNameOf(src),
            maxSize = Config.Party.maxSize,
            size = #members,
            selectedMode = defaultModeId(),
            launching = false,
            members = members,
        },
        modes = modesForState(),
        queue = queueState and queueState() or nil,
    }
end

local function sendState(src)
    local state = buildState(src)
    if state then
        TriggerClientEvent('gf_lobby:state', src, state)
    end
end

local function broadcastParty(partyId)
    local party = Parties[partyId]
    if not party then return end
    for _, member in ipairs(party.members) do
        if Players[member] and Players[member].inLobby then
            sendState(member)
        end
    end
end

-- ---------------------------------------------------------------------------
--  File de recherche serveur (Attaque de zone)
-- ---------------------------------------------------------------------------

local function queueMin()
    return (Config.Matchmaking and Config.Matchmaking.attackMin) or 20
end

local function queueMax()
    return (Config.Matchmaking and Config.Matchmaking.attackMax) or 30
end

local function queueSize()
    local n = 0
    for _ in pairs(Queue.members) do n = n + 1 end
    return n
end

local function eligibleForQueue(src)
    local player = Players[src]
    return player ~= nil and player.inLobby == true and type(player.character) == 'table'
end

-- Recalcule l'éligibilité de tous les joueurs présents dans le lobby.
-- Un joueur sans personnage ou hors lobby est retiré ; un nouvel arrivant
-- avec personnage est ajouté automatiquement pendant une recherche active.
local function refreshQueue()
    if not Queue.active then return false end
    for src in pairs(Queue.members) do
        if not eligibleForQueue(src) then
            Queue.members[src] = nil
        end
    end
    for src in pairs(Players) do
        if eligibleForQueue(src) then
            Queue.members[src] = true
        end
    end
    if Queue.owner ~= nil and not eligibleForQueue(Queue.owner) then
        -- Chef parti : la recherche reste serveur, plus personne ne peut
        -- l'annuler. Elle se remplit jusqu'au seuil puis lance la partie.
        Queue.owner = nil
    end
    return true
end

queueState = function()
    if not Queue.active then return nil end
    return {
        mode = Queue.mode or 'attack',
        size = queueSize(),
        min = queueMin(),
        max = queueMax(),
        ownerId = Queue.owner,
    }
end

local function broadcastQueueState()
    for _, rawId in ipairs(GetPlayers()) do
        local src = tonumber(rawId)
        local player = src and Players[src]
        if player and player.inLobby then
            sendState(src)
        end
    end
end

local function stopQueue(reason)
    if not Queue.active then return end
    Queue.active = false
    Queue.mode = nil
    Queue.owner = nil
    Queue.members = {}
    broadcastQueueState()
    if reason then log(('recherche attack arrêtée : %s'):format(reason)) end
end

local function createParty(src)
    local player = Players[src]
    if not player then return nil end

    local id = nextPartyId
    nextPartyId = nextPartyId + 1

    local party = {
        id = id,
        leader = src,
        members = { src },
        selectedMode = defaultModeId(),
        launching = false,
    }
    Parties[id] = party
    player.partyId = id
    setBucket(src, id)
    return party
end

local function removeFromParty(src)
    local player = Players[src]
    if not player then return end

    local party = findParty(src)
    if not party then
        player.partyId = nil
        return
    end

    local index = nil
    for i, member in ipairs(party.members) do
        if member == src then
            index = i
            break
        end
    end
    if not index then
        player.partyId = nil
        return
    end

    table.remove(party.members, index)
    player.partyId = nil

    if #party.members == 0 then
        Parties[party.id] = nil
        return
    end

    if party.leader == src then
        party.leader = party.members[1]
        notify(party.leader, "Tu es le nouveau chef de l'escouade.", 'info')
    end

    broadcastParty(party.id)
end

local function joinLobby(src)
    local player = ensurePlayer(src)
    if not player then return end

    player.inLobby = true
    if not findParty(src) then
        createParty(src)
    end
    setBucket(src, player.partyId)
    broadcastParty(player.partyId)
    if Queue.active then
        refreshQueue()
        broadcastQueueState()
    end
end

local function leaveLobby(src)
    local player = Players[src]
    if not player or not player.inLobby then return end

    player.inLobby = false
    removeFromParty(src)
    player.partyId = nil
    if Queue.active then
        refreshQueue()
        if queueSize() == 0 then
            stopQueue('file vide')
        else
            broadcastQueueState()
        end
    end
    TriggerClientEvent('gf_lobby:close', src)
end

local function invitePayload(invite)
    local party = Parties[invite.partyId]
    local leader = party and party.leader or invite.from
    return {
        partyId = invite.partyId,
        from = {
            id = invite.from,
            name = displayNameOf(invite.from),
        },
        leader = {
            id = leader,
            name = displayNameOf(leader),
        },
        expiresIn = math.max(0, invite.expiresAt - os.time()) * 1000,
    }
end

local function clearExpiredInvite(target)
    local invite = Invites[target]
    if not invite then return nil end
    if os.time() > invite.expiresAt then
        Invites[target] = nil
        return nil
    end
    return invite
end

local function acceptInvite(src, invite)
    local player = Players[src]
    local party = Parties[invite.partyId]
    if not player or not player.inLobby then
        notify(src, "Tu n'es plus dans le lobby.", 'error')
        return
    end
    if not player.character then
        notify(src, 'Crée ton personnage avant de rejoindre une escouade.', 'error')
        return
    end
    if not party then
        notify(src, "Cette escouade n'existe plus.", 'error')
        return
    end
    if #party.members >= Config.Party.maxSize then
        notify(src, "L'escouade est complète.", 'error')
        return
    end
    for _, member in ipairs(party.members) do
        if member == src then
            notify(src, 'Tu fais déjà partie de cette escouade.', 'error')
            return
        end
    end

    local current = findParty(src)
    if current and #current.members > 1 then
        notify(src, "Quitte ton escouade actuelle avant d'en rejoindre une autre.", 'error')
        return
    end

    if current then
        removeFromParty(src)
    end
    Invites[src] = nil

    party.members[#party.members + 1] = src
    player.partyId = party.id
    setBucket(src, party.id)
    notify(src, "Tu as rejoint l'escouade.", 'success')
    broadcastParty(party.id)
end

local function leaveParty(src)
    local player = Players[src]
    local party = findParty(src)
    if not player or not player.inLobby or not party then
        notify(src, "Tu n'es pas dans une escouade.", 'error')
        return
    end
    if #party.members <= 1 then
        notify(src, 'Tu es déjà seul dans ton escouade.', 'info')
        return
    end

    removeFromParty(src)
    createParty(src)
    sendState(src)
end

local function kickMember(src, target)
    local player = Players[src]
    local party = findParty(src)
    if not player or not party or party.leader ~= src then
        notify(src, "Seul le chef peut exclure un membre.", 'error')
        return
    end
    if target == src then
        notify(src, 'Tu ne peux pas t’exclure toi-même.', 'error')
        return
    end

    local memberPlayer = Players[target]
    if not memberPlayer or memberPlayer.partyId ~= party.id then
        notify(src, "Ce joueur n'est pas dans ton escouade.", 'error')
        return
    end

    removeFromParty(target)
    -- Recréer une escouade solo uniquement si le joueur est encore dans le
    -- lobby : sinon il resterait 'inLobby=false' avec une party fantôme.
    if memberPlayer.inLobby then
        createParty(target)
        sendState(target)
    end
    notify(target, "Tu as été exclu de l'escouade.", 'info')
    notify(src, "Membre exclu de l'escouade.", 'success')
end

local function selectMode(src, modeId)
    local player = Players[src]
    local party = findParty(src)
    if not player or not party or party.leader ~= src then
        notify(src, 'Seul le chef choisit le mode de jeu.', 'error')
        return
    end

    local mode = findMode(modeId)
    if not mode or not isModeAvailable(mode) then
        notify(src, 'Ce mode n’est pas disponible.', 'error')
        return
    end

    local now = GetGameTimer()
    if now - player.lastMode < Config.Party.modeCooldown * 1000 then
        notify(src, 'Patiente avant de changer de mode.', 'info')
        return
    end

    player.lastMode = now
    party.selectedMode = mode.id
    broadcastParty(party.id)
end

-- Lance une recherche serveur globale pour Attaque de zone. Aucune condition
-- sur la taille de l'escouade : le chef d'une escouade solo peut lancer.
local function startQueue(src, mode, party)
    local now = GetGameTimer()
    local player = Players[src]

    if Queue.active then
        notify(src, ('Recherche %s en cours : %d/%d joueurs.'):format(mode.label, queueSize(), queueMin()), 'info')
        return
    end

    refreshQueue()
    if queueSize() == 0 then
        notify(src, 'Aucun joueur éligible dans le lobby.', 'error')
        return
    end

    player.lastMode = now
    Queue.active = true
    Queue.mode = mode.id
    Queue.owner = src
    Queue.members = {}
    refreshQueue()

    log(('startQueue %s -> %s, %d joueur(s), seuil=%d'):format(src, mode.id, queueSize(), queueMin()))
    notify(src, ('Recherche lancée : %d/%d joueurs.'):format(queueSize(), queueMin()), 'success')
    broadcastQueueState()
end

-- Annulation par le chef : vider la file, arrêter la recherche, restaurer
-- l'état NUI. Aucun close explicite : la NUI reste ouverte pendant l'attente.
local function cancelQueue(src)
    if not Queue.active then return false end
    local party = findParty(src)
    if not party or party.leader ~= src then
        notify(src, 'Seul le chef peut annuler la recherche.', 'error')
        return false
    end
    if Queue.owner and Queue.owner ~= src then
        notify(src, 'La recherche a été lancée par un autre chef.', 'error')
        return false
    end
    stopQueue('annulée par le chef')
    notify(src, 'Recherche annulée.', 'info')
    return true
end

-- Lancement effectif quand le seuil est atteint. `members` est une copie de
-- la file au moment du seuil : les joueurs qui quittent le lobby entre le
-- seuil et le SetTimeout sont ignorés par les contrôles ci-dessous.
local function launchQueuedMatch(src, mode, members)
    local party = findParty(src)
    if not party then return end
    local player = Players[src]
    local now = GetGameTimer()

    player.lastMode = now
    local affectedParties = {}
    local function markLaunching(targetParty)
        if not targetParty then return end
        targetParty.selectedMode = mode.id
        targetParty.launching = true
        affectedParties[targetParty.id] = targetParty
    end

    markLaunching(party)
    for _, member in ipairs(members) do
        markLaunching(findParty(member))
        TriggerClientEvent('gf_lobby:launching', member, {
            mode = mode.id,
            label = mode.label,
        })
    end

    local partyId = party.id
    log(('launchQueuedMatch %s -> %s, %d joueur(s), seuil=%d'):format(src, mode.id, #members, queueMin()))

    local function resetLaunching()
        local changed = false
        for id, affected in pairs(affectedParties) do
            if Parties[id] == affected and affected.launching then
                affected.launching = false
                broadcastParty(id)
                changed = true
            end
        end
        return changed
    end

    SetTimeout(700, function()
        local current = Parties[partyId]
        if not current then
            resetLaunching()
            for _, member in ipairs(members) do
                local memberPlayer = Players[member]
                if memberPlayer and memberPlayer.inLobby then sendState(member) end
            end
            log('launchQueuedMatch : parti du chef disparue, lancement annulé')
            return
        end
        if not current.launching then return end

        local launched = 0
        for _, member in ipairs(members) do
            if eligibleForQueue(member) then
                local okMode, currentMode = pcall(function()
                    return exports.gf_core:GetMode(member)
                end)
                local already = okMode and currentMode == mode.id
                local ok, result = false, false
                if not already then
                    ok, result = pcall(function()
                        return exports.gf_core:SetMode(member, mode.id)
                    end)
                end
                if already or (ok and result ~= false) then
                    launched = launched + 1
                    -- gf_core:modeChanged ferme déjà l'UI côté client ; ne pas
                    -- envoyer de close explicite ici (le state doit rester
                    -- cohérent jusqu'à la replication de gf_core).
                end
            end
        end

        log(('launchQueuedMatch %s : %d/%d lancé(s)'):format(src, launched, #members))
        if launched < #members then
            -- Échec total ou partiel : restore launching et state AVANT toute
            -- notification pour que le chef voit un bouton JOUER utilisable.
            resetLaunching()
            for _, member in ipairs(members) do
                local memberPlayer = Players[member]
                if memberPlayer and memberPlayer.inLobby then
                    sendState(member)
                end
            end
            local leader = current.leader
            if GetPlayerName(leader) then
                if launched == 0 then
                    notify(leader, 'Impossible de lancer la partie.', 'error')
                else
                    notify(leader, ('Partie lancée pour %d/%d joueurs.'):format(launched, #members), 'error')
                end
            end
        end
    end)
end

local function launchParty(src, modeId)
    local player = Players[src]
    local party = findParty(src)
    if not player or not party or party.leader ~= src then
        notify(src, 'Seul le chef peut lancer la partie.', 'error')
        return
    end
    if party.launching then
        notify(src, 'La partie est déjà en cours de lancement.', 'info')
        return
    end

    local mode = findMode(modeId)
    if not mode or not isModeAvailable(mode) then
        notify(src, 'Ce mode n’est pas disponible.', 'error')
        return
    end

    local now = GetGameTimer()
    if now - player.lastMode < Config.Party.modeCooldown * 1000 then
        notify(src, 'Patiente avant de lancer la partie.', 'info')
        return
    end

    -- Attaque de zone : recherche serveur globale, pas de condition d'escouade.
    if mode.id == 'attack' then
        startQueue(src, mode, party)
        return
    end

    -- Autres modes (Redzone) : comportement d'escouade inchangé.
    local members = {}
    for _, member in ipairs(party.members) do members[#members + 1] = member end
    if #members == 0 then
        notify(src, 'Ton escouade est vide.', 'error')
        return
    end

    for _, member in ipairs(members) do
        local memberPlayer = Players[member]
        if not memberPlayer or not memberPlayer.inLobby then
            notify(src, "Tous les membres doivent être dans le lobby.", 'error')
            return
        end
        if not memberPlayer.character then
            notify(src, 'Tous les membres doivent avoir créé leur personnage.', 'error')
            return
        end
    end

    local requiredPlayers = mode.minPlayers or 1
    if #members < requiredPlayers then
        notify(src, ('Il faut au moins %d joueurs pour lancer %s.'):format(requiredPlayers, mode.label), 'error')
        return
    end

    player.lastMode = now
    party.selectedMode = mode.id
    party.launching = true

    for _, member in ipairs(members) do
        TriggerClientEvent('gf_lobby:launching', member, {
            mode = mode.id,
            label = mode.label,
        })
    end

    local partyId = party.id
    log(('launchParty %s -> %s, %d membre(s), minPlayers=%d'):format(src, mode.id, #members, requiredPlayers))

    local function resetLaunching()
        local current = Parties[partyId]
        if not current or not current.launching then return false end
        current.launching = false
        broadcastParty(partyId)
        return true
    end

    SetTimeout(700, function()
        local current = Parties[partyId]
        if not current then return end
        if not current.launching then return end

        local launched = 0
        for _, member in ipairs(members) do
            local memberPlayer = Players[member]
            if memberPlayer and memberPlayer.inLobby and memberPlayer.partyId == partyId then
                local okMode, currentMode = pcall(function()
                    return exports.gf_core:GetMode(member)
                end)
                local already = okMode and currentMode == mode.id
                local ok, result = false, false
                if not already then
                    ok, result = pcall(function()
                        return exports.gf_core:SetMode(member, mode.id)
                    end)
                end
                if already or (ok and result ~= false) then
                    launched = launched + 1
                    -- gf_core:modeChanged ferme déjà l'UI côté client ; ne pas
                    -- envoyer de close explicite ici (le state doit rester
                    -- cohérent jusqu'à la replication de gf_core).
                end
            end
        end

        log(('launchParty %s : %d/%d lancé(s)'):format(src, launched, #members))
        if launched < #members then
            -- Échec total ou partiel : restore launching et state AVANT toute
            -- notification pour que le chef voit un bouton JOUER utilisable.
            resetLaunching()
            for _, member in ipairs(members) do
                local memberPlayer = Players[member]
                if memberPlayer and memberPlayer.inLobby then
                    sendState(member)
                end
            end
            local leader = current.leader
            if GetPlayerName(leader) then
                if launched == 0 then
                    notify(leader, 'Impossible de lancer la partie.', 'error')
                else
                    notify(leader, ('Partie lancée pour %d/%d joueurs.'):format(launched, #members), 'error')
                end
            end
        end
    end)
end

-- Seuil atteint : on fige la file, on l'arrête (plus d'inscription pendant
-- le lancement) et on lance tous les joueurs via gf_core:SetMode.
local function checkQueueThreshold()
    if not Queue.active then return end
    if queueSize() < queueMin() then return end
    -- Un match d'Attaque est déjà en cours ou complet : la file attend la fin.
    if Queue.mode == 'attack' and GetResourceState('gf_attack') == 'started' then
        local ok, canJoin = pcall(function() return exports.gf_attack:CanJoin() end)
        if ok and canJoin == false then return end
    end

    local members = {}
    for src in pairs(Queue.members) do
        if eligibleForQueue(src) then members[#members + 1] = src end
    end
    local modeId = Queue.mode
    local owner = Queue.owner
    Queue.active = false
    Queue.mode = nil
    Queue.owner = nil
    Queue.members = {}
    broadcastQueueState()

    if #members < queueMin() then
        log(('checkQueueThreshold : seulement %d joueur(s) éligible(s), recherche annulée'):format(#members))
        return
    end
    local max = queueMax()
    if #members > max then
        table.sort(members)
        for i = #members, max + 1, -1 do members[i] = nil end
        log(('checkQueueThreshold : file plafonnée à %d joueur(s)'):format(max))
    end

    -- Le chef peut avoir quitté le lobby pendant l'attente : on prend le
    -- premier membre encore présent comme référence pour party.launching.
    if not owner or not findParty(owner) then
        owner = nil
        for _, src in ipairs(members) do
            if findParty(src) then owner = src break end
        end
    end
    if not owner then
        log('checkQueueThreshold : aucun chef disponible, recherche abandonnée')
        return
    end
    local mode = findMode(modeId)
    if not mode then return end
    launchQueuedMatch(owner, mode, members)
end

CreateThread(function()
    while true do
        Wait(500)
        if Queue.active then checkQueueThreshold() end
    end
end)

-- ---------------------------------------------------------------------------
--  Événements NUI → serveur
-- ---------------------------------------------------------------------------

RegisterNetEvent('gf_lobby:createCharacter', function(payload)
    local src = source
    local player = ensurePlayer(src)
    if not player or not player.inLobby then return end
    if player.character then
        TriggerClientEvent('gf_lobby:createResult', src, { ok = false, error = 'Tu as déjà un personnage.' })
        return
    end

    local now = GetGameTimer()
    if now - player.lastCreate < 2000 then
        TriggerClientEvent('gf_lobby:createResult', src, { ok = false, error = 'Patiente avant de réessayer.' })
        return
    end
    player.lastCreate = now

    local character = normalizeCharacter(payload)
    if not character then
        TriggerClientEvent('gf_lobby:createResult', src, {
            ok = false,
            error = ('Personnage invalide : nom %d à %d caractères, genre, seed ou carnation.'):format(
                Config.Character.nameMin, Config.Character.nameMax
            ),
        })
        return
    end

    player.character = character
    if player.persistent then
        Store[player.identifier] = character
        saveCharacters()
    end

    TriggerClientEvent('gf_lobby:createResult', src, { ok = true })
    notify(src, 'Personnage créé. Bienvenue dans le lobby.', 'success')
    sendState(src)
    if player.partyId then broadcastParty(player.partyId) end
    if Queue.active then
        refreshQueue()
        broadcastQueueState()
    end
end)

RegisterNetEvent('gf_lobby:requestState', function()
    local src = source
    local player = ensurePlayer(src)
    if not player then return end

    local now = GetGameTimer()
    if now - player.lastState < Config.RequestCooldownMs then return end
    player.lastState = now

    -- Ne jamais anticiper la création de party sur un mode nil/indisponible :
    -- gf_core n'a pas encore décidé, on renvoie un état sans fermer la NUI.
    local ok, mode
    if not player.inLobby then
        ok, mode = pcall(function() return exports.gf_core:GetMode(src) end)
        if ok and mode and mode ~= 'lobby' then
            -- Le joueur est réellement dans un autre mode : la NUI doit se fermer.
            TriggerClientEvent('gf_lobby:close', src)
            return
        end
        if ok and mode == 'lobby' then
            -- Mode lobby explicite : recovery idempotent.
            joinLobby(src)
        elseif not ok or not mode then
            log(('requestState %s : gf_core sans mode, état sans join'):format(src))
        end
    end
    sendState(src)
end)

RegisterNetEvent('gf_lobby:requestPlayers', function()
    local src = source
    local player = Players[src]
    local party = findParty(src)
    if not player or not player.inLobby or not party then return end

    -- Anti-spam : une requête trop rapprochée est ignorée. La NUI demande la
    -- liste à l'ouverture de la modale (timer 5 s), pas en boucle.
    local now = GetGameTimer()
    if now - player.lastPlayers < Config.RequestCooldownMs then return end
    player.lastPlayers = now

    local list = {}
    for _, rawId in ipairs(GetPlayers()) do
        local other = tonumber(rawId)
        if other and other ~= src then
            -- Lecture seule : ne pas joindre/resync un autre joueur depuis la
            -- modale (aucun effet de bord sur son bucket ni sa party).
            local otherPlayer = Players[other]
            if otherPlayer and otherPlayer.inLobby and otherPlayer.character then
                local inParty = false
                for _, member in ipairs(party.members) do
                    if member == other then inParty = true break end
                end
                if not inParty then
                    local otherParty = findParty(other)
                    list[#list + 1] = {
                        id = other,
                        name = displayNameOf(other),
                        partySize = otherParty and #otherParty.members or 1,
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)

    TriggerClientEvent('gf_lobby:players', src, { players = list })
end)

RegisterNetEvent('gf_lobby:invite', function(payload)
    local src = source
    local target = tonumber(type(payload) == 'table' and payload.id or payload)
    local player = Players[src]
    local party = findParty(src)
    if not player or not player.inLobby or not party then return end
    if not player.character then
        notify(src, 'Crée ton personnage avant d’inviter.', 'error')
        return
    end
    if not target or target == src then
        notify(src, 'Joueur invalide.', 'error')
        return
    end

    local targetPlayer = Players[target]
    if not targetPlayer or not targetPlayer.inLobby then
        notify(src, 'Ce joueur n’est pas dans le lobby.', 'error')
        return
    end
    if not targetPlayer.character then
        notify(src, 'Ce joueur doit créer un personnage avant d’être invité.', 'error')
        return
    end
    if targetPlayer.partyId == party.id then
        notify(src, 'Ce joueur est déjà dans ton escouade.', 'error')
        return
    end
    if #party.members >= Config.Party.maxSize then
        notify(src, "L'escouade est complète.", 'error')
        return
    end

    local now = os.time()
    if now - player.lastInvite < Config.Party.inviteCooldown then
        notify(src, 'Patiente avant d’envoyer une autre invitation.', 'info')
        return
    end
    player.lastInvite = now

    local invite = {
        partyId = party.id,
        from = src,
        expiresAt = now + Config.Party.inviteTimeout,
    }
    Invites[target] = invite
    TriggerClientEvent('gf_lobby:invite', target, invitePayload(invite))
    TriggerClientEvent('gf_lobby:inviteResult', src, {
        ok = true,
        message = ('Invitation envoyée à %s.'):format(displayNameOf(target)),
    })

    SetTimeout(Config.Party.inviteTimeout * 1000, function()
        if Invites[target] == invite then
            Invites[target] = nil
        end
    end)
end)

RegisterNetEvent('gf_lobby:respondInvite', function(payload)
    local src = source
    local partyId = tonumber(type(payload) == 'table' and payload.partyId or nil)
    local accept = type(payload) == 'table' and payload.accept == true
    local invite = clearExpiredInvite(src)

    if not invite or not partyId or invite.partyId ~= partyId then
        notify(src, 'Invitation expirée ou introuvable.', 'error')
        return
    end

    if not accept then
        Invites[src] = nil
        TriggerClientEvent('gf_lobby:inviteResult', src, { ok = true, message = 'Invitation refusée.' })
        return
    end

    acceptInvite(src, invite)
end)

RegisterNetEvent('gf_lobby:leaveParty', function()
    leaveParty(source)
end)

RegisterNetEvent('gf_lobby:kickMember', function(payload)
    local src = source
    local target = tonumber(type(payload) == 'table' and payload.id or payload)
    if not target then
        notify(src, 'Joueur invalide.', 'error')
        return
    end
    kickMember(src, target)
end)

RegisterNetEvent('gf_lobby:selectMode', function(payload)
    local src = source
    local modeId = type(payload) == 'table' and payload.mode or payload
    if type(modeId) ~= 'string' then return end
    -- Annulation de la recherche serveur : le client ne peut pas envoyer
    -- `{cancel=true}` via `play` (le relais client ne garde que `mode`), mais
    -- `selectMode` accepte une charge utile table et relaie `cancel`.
    if type(payload) == 'table' and payload.cancel == true then
        cancelQueue(src)
        return
    end
    selectMode(src, modeId)
end)

RegisterNetEvent('gf_lobby:play', function(payload)
    local src = source
    local modeId = type(payload) == 'table' and payload.mode or payload
    if type(modeId) ~= 'string' then return end
    launchParty(src, modeId)
end)

-- ---------------------------------------------------------------------------
--  Cycle de vie
-- ---------------------------------------------------------------------------

AddEventHandler('gf:modeJoined', function(src, mode)
    src = tonumber(src)
    if not src then return end
    ensurePlayer(src)
    if mode == 'lobby' then
        joinLobby(src)
    else
        leaveLobby(src)
    end
end)

AddEventHandler('gf:modeLeft', function(src, _mode)
    src = tonumber(src)
    if not src then return end
    leaveLobby(src)
end)

AddEventHandler('playerDropped', function(_reason)
    local src = source
    local player = Players[src]
    if not player then return end

    player.inLobby = false
    removeFromParty(src)
    if Queue.active then
        refreshQueue()
        if queueSize() == 0 then
            stopQueue('file vide')
        else
            broadcastQueueState()
        end
    end
    Invites[src] = nil
    for target, invite in pairs(Invites) do
        if invite.from == src then Invites[target] = nil end
    end
    Players[src] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    saveCharacters()
    for _, src in ipairs(GetPlayers()) do
        local target = tonumber(src)
        if target then
            TriggerClientEvent('gf_lobby:close', target)
        end
    end
end)

RegisterCommand('resetchar', function(src, args)
    src = tonumber(src) or 0
    if src ~= 0 and not IsPlayerAceAllowed(src, ADMIN_ACE) then
        notify(src, 'Accès administrateur requis.', 'error')
        return
    end

    local target = tonumber(args[1])
    if not target then
        if src == 0 then
            print('Usage : resetchar <id>')
        else
            notify(src, 'Usage : /resetchar <id>', 'info')
        end
        return
    end
    if not GetPlayerName(target) then
        if src == 0 then
            print(('Joueur %d introuvable.'):format(target))
        else
            notify(src, 'Joueur introuvable.', 'error')
        end
        return
    end

    local player = Players[target]
    if player and player.identifier then
        Store[player.identifier] = nil
        player.character = nil
        saveCharacters()
        if player.inLobby then sendState(target) end
        notify(target, 'Ton personnage a été réinitialisé.', 'info')
    else
        local identifier = findIdentifier(target)
        Store[identifier] = nil
        saveCharacters()
    end

    if src ~= 0 then notify(src, 'Personnage réinitialisé.', 'success') end
end, false)

CreateThread(function()
    loadCharacters()
    Wait(500)

    for _, rawId in ipairs(GetPlayers()) do
        local src = tonumber(rawId)
        if src then
            ensurePlayer(src)
            local ok, mode = pcall(function()
                return exports.gf_core:GetMode(src)
            end)
            if ok and mode == 'lobby' then
                joinLobby(src)
            end
        end
    end
end)
