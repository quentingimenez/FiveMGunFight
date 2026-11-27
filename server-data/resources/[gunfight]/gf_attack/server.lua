-- =============================================================================
--  gf_attack - SERVEUR (exécution des effets rendus par rules.lua)
--
--  Ce fichier ne prend AUCUNE décision de jeu : phases, équipes, états vivant,
--  scores, manches, échéances, matchOver, départs, morts et équilibrage
--  viennent exclusivement de AttackRules. On ne garde ici que les natives
--  FiveM, les événements/commandes réseau, les annonces et l'affichage.
--
--  Les durées de Config sont exprimées en secondes ; CONFIG_MANCHES est le
--  seul point de conversion vers les millisecondes attendues par les règles.
-- =============================================================================

local core = exports.gf_core

local ADMIN_REQUIS = 'Réservé aux administrateurs. Tape /whoami pour voir ton identifiant.'

-- SEUL point de conversion des secondes (Config) vers les millisecondes (règles).
local CONFIG_MANCHES = {
    PlayersToStart = Config.PlayersToStart,
    MaxPlayers = Config.MaxPlayers,
    WinRounds = Config.WinRounds,
    SwapSidesEveryRound = Config.SwapSidesEveryRound,
    SelectTimeMs = Config.SelectTime * 1000,
    PlacementTimeMs = Config.PlacementTime * 1000,
    RoundTimeMs = Config.RoundTime * 1000,
    EndDelayMs = Config.EndDelay * 1000,
    MatchEndDelayMs = Config.MatchEndDelay * 1000,
}

local etat = AttackRules.nouveau(CONFIG_MANCHES, math.random)

local Choix = {}          -- [src] = choix d'armes (gardé d'une manche à l'autre)
local Noms = {}           -- [src] = nom à l'arrivée (conservé pour les joueurs partis)
local classementSale = false

-- ---------------------------------------------------------------- Utilitaires
-- Cap (heading GTA) pour regarder du point (x,y) vers (tx,ty)
local function headingTo(x, y, tx, ty)
    return (math.deg(math.atan(-(tx - x), ty - y)) + 360.0) % 360.0
end

-- ---------------------------------------------------------------- Maps
-- Une map = { name, points{ {x,y,z} }, attackSpawn{x,y,z,h}, defenseSpawn{x,y,z,h} }
-- On y ajoute center (centre) et radius (rayon englobant) pour l'affichage.
local function finalizeMap(m)
    local x, y, z = 0.0, 0.0, 0.0
    for _, p in ipairs(m.points) do x, y, z = x + p.x, y + p.y, z + p.z end
    local n = #m.points
    local c = { x = x / n, y = y / n, z = z / n }
    local r = 0.0
    for _, p in ipairs(m.points) do
        local d = math.sqrt((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2)
        if d > r then r = d end
    end
    m.center, m.radius = c, r
    return m
end

-- Zone de secours (config.lua, cercle) -> polygone à 16 côtés
local function fallbackMap(z)
    local c = z.center
    local points = {}
    for i = 0, 15 do
        local a = i / 16 * 2 * math.pi
        points[#points + 1] = { x = c.x + math.cos(a) * z.radius, y = c.y + math.sin(a) * z.radius, z = c.z }
    end
    local rad = math.rad(z.attackFrom or 0)
    local d = z.radius + Config.AttackSpawnDistance
    local ax, ay = c.x + math.sin(rad) * d, c.y + math.cos(rad) * d
    return {
        name = z.name,
        points = points,
        attackSpawn = { x = ax, y = ay, z = c.z, h = headingTo(ax, ay, c.x, c.y) },
        defenseSpawn = { x = c.x, y = c.y, z = c.z, h = 0.0 },
    }
end

local function mapList()
    local ok, maps = pcall(function() return exports.gf_maps:GetActiveMaps('attack') end)
    if ok and type(maps) == 'table' and #maps > 0 then return maps end
    local list = {}
    for _, z in ipairs(Config.Zones) do list[#list + 1] = fallbackMap(z) end
    return list
end

local currentMap = nil
local zoneIndex = 1

local function loadMap(index)
    local list = mapList()
    zoneIndex = ((index - 1) % #list) + 1
    currentMap = finalizeMap(list[zoneIndex])
end

-- Identifiant stable d'une carte pour le vote du lobby : les maps de gf_maps
-- ont un id, les zones de secours de config.lua n'en ont pas (secours_N).
local function choiceId(m, i)
    if type(m) == 'table' and type(m.id) == 'string' and m.id ~= '' then return m.id end
    return 'secours_' .. i
end

loadMap(zoneIndex)

local function zone() return currentMap end

-- Même contour que celui utilisé par le client pour les limites de la zone.
local function attackerInZone()
    local points = zone().points
    for src, team in pairs(etat.equipes) do
        if team == etat.attaquants and etat.vivants[src] then
            local ped = GetPlayerPed(src)
            if ped ~= 0 then
                local pos = GetEntityCoords(ped)
                local inside, j = false, #points
                for i = 1, #points do
                    local a, b = points[i], points[j]
                    if (a.y > pos.y) ~= (b.y > pos.y)
                        and pos.x < (b.x - a.x) * (pos.y - a.y) / (b.y - a.y) + a.x then
                        inside = not inside
                    end
                    j = i
                end
                if inside then return true end
            end
        end
    end
    return false
end

-- Affichage du camp adverse : purement dérivé de etat.attaquants.
local function defenders()
    return etat.attaquants == 'A' and 'B' or 'A'
end

local function eachPlayer(fn)
    for src in pairs(etat.equipes) do fn(src) end
end

local function announce(src, title, sub, ms)
    TriggerClientEvent('gf_ui:announce', src, { title = title, subtitle = sub, duration = ms or 4000 })
end

local function announceAll(title, sub, ms)
    eachPlayer(function(src) announce(src, title, sub, ms) end)
end

-- Rang du joueur dans son équipe (1, 2, 3...) pour ranger les voitures
local function slotOf(src)
    local t, list = etat.equipes[src], {}
    for s, tm in pairs(etat.equipes) do if tm == t then list[#list + 1] = s end end
    table.sort(list)
    for i, s in ipairs(list) do if s == src then return i end end
    return 1
end

-- Position d'apparition de l'équipe, en formation, tournée vers la zone.
--  - en voiture : rangées de Config.VehicleColumns voitures côte à côte,
--    serrées mais sans se chevaucher, les rangées suivantes derrière ;
--  - à pied : un groupe compact (1 joueur au centre, puis des anneaux de 6,
--    12, 18... joueurs autour), chacun à sa place.
local function spawnPos(src, inVehicle)
    local z = zone()
    local sp = AttackRules.roleEquipe(etat, etat.equipes[src]) == 'defense' and z.defenseSpawn or z.attackSpawn
    local h = math.rad(headingTo(sp.x, sp.y, z.center.x, z.center.y))
    local fx, fy = -math.sin(h), math.cos(h)   -- vers l'avant (la zone)
    local rx, ry = math.cos(h), math.sin(h)    -- vers le côté
    local i = slotOf(src) - 1
    local side, back = 0.0, 0.0

    if inVehicle then
        local cols = Config.VehicleColumns
        local col, row = i % cols, math.floor(i / cols)
        side = (col - (cols - 1) / 2) * Config.VehicleSideSpacing
        back = row * Config.VehicleRowSpacing
    elseif i > 0 then
        local ring, idx, ringSize = 1, i - 1, 6
        while idx >= ringSize do
            idx, ring = idx - ringSize, ring + 1
            ringSize = 6 * ring
        end
        local a = idx / ringSize * 2 * math.pi
        side = math.cos(a) * ring * Config.FootSpacing
        back = math.sin(a) * ring * Config.FootSpacing
    end

    local x = sp.x + rx * side - fx * back
    local y = sp.y + ry * side - fy * back
    return x, y, sp.z, math.deg(h) % 360.0
end

-- opts : vehicle (bool), freeze, protected, weapons (bool : armes choisies)
local function spawnRole(src, opts)
    local inVehicle = opts.vehicle and AttackRules.roleDe(etat, src) == 'attack'
    local x, y, z, h = spawnPos(src, inVehicle)
    local weapons = nil
    if opts.weapons then
        weapons = core:BuildWeaponList(core:ResolveSelection(src, Choix[src]), src)
    end
    core:Spawn(src, {
        x = x, y = y, z = z, heading = h,
        -- Seuls les attaquants ont une voiture : les défenseurs apparaissent à pied dans la zone
        vehicle = inVehicle and Config.Vehicle or nil,
        weapons = weapons, armour = weapons and core:GetSelectionSettings().armour or nil,
        freeze = opts.freeze, protected = opts.protected,
    })
end

local function toSpectator(src)
    if not etat.equipes[src] then return end
    local c = zone().center
    -- keepVehicle : la voiture du joueur mort reste dans la manche
    core:Spawn(src, { x = c.x, y = c.y, z = c.z + 45.0, heading = 0.0, spectator = true, keepVehicle = true })
    TriggerClientEvent('gf_attack:spectate', src, true)
end

-- Menu de choix des 2 armes (pendant la phase de choix)
local function openLoadout(src)
    local restant = math.max(math.ceil((etat.echeance - GetGameTimer()) / 1000), 1)
    local settings = core:GetSelectionSettings()
    TriggerClientEvent('gf_ui:loadout_open', src, {
        title = 'Choisis tes 2 armes',
        weapons = core:GetOwnedWeapons(src),
        selected = core:ResolveSelection(src, Choix[src]),
        count = settings.count,
        seconds = restant,
    })
end

local function sendZone(src)
    local z = zone()
    TriggerClientEvent('gf_attack:zone', src, {
        name = z.name,
        points = z.points,
        center = z.center,
        radius = z.radius,
        defenders = defenders(),
        phase = etat.phase,
        damage = Config.OutOfZoneDamage,
        colors = { A = Config.Teams.A.color, B = Config.Teams.B.color },
    })
end

local function sendZoneAll() eachPlayer(sendZone) end

-- ---------------------------------------------------------------- Soins
-- Bandages et kevlars : le nombre est tenu par le serveur, le client ne fait
-- que jouer l'animation puis appliquer le soin que le serveur a autorisé.
local Items = {}   -- [src] = { bandage = n, kevlar = n }
local Using = {}   -- [src] = GetGameTimer() de fin de l'utilisation en cours

local function sendItems(src)
    TriggerClientEvent('gf_attack:items', src, Items[src])
end

local function resetItems(src)
    Items[src] = { bandage = Config.StartBandages, kevlar = Config.StartKevlars }
    Using[src] = nil
    sendItems(src)
end

local function clearItems(src)
    Items[src], Using[src] = nil, nil
    if GetPlayerName(src) then TriggerClientEvent('gf_attack:items', src, nil) end
end

RegisterNetEvent('gf_attack:useItem', function(item)
    local src = source
    local def = type(item) == 'string' and Config.Items[item] or nil
    if not def or not etat.equipes[src] or not etat.vivants[src] then return end
    if etat.phase ~= 'place' and etat.phase ~= 'live' then return end
    local t = GetGameTimer()
    if Using[src] and t < Using[src] then return end   -- une seule utilisation à la fois
    local inv = Items[src]
    if not inv or (inv[item] or 0) <= 0 then return end
    inv[item] = inv[item] - 1
    Using[src] = t + math.floor(def.duration * 1000)
    TriggerClientEvent('gf_attack:applyItem', src, item)
    TriggerEvent('gf:itemUsed', src, def.stat, def.amount, math.floor(def.duration * 1000))
    sendItems(src)
end)

-- ---------------------------------------------------------------- HUD & classement
local function phaseLabel()
    return ({ waiting = 'En attente de joueurs', select = 'Choix des armes', place = 'Placement', live = 'Combat', ended = 'Fin de manche' })[etat.phase]
end

local function sendHud()
    local remaining = etat.echeance > 0 and math.max(math.ceil((etat.echeance - GetGameTimer()) / 1000), 0) or nil
    local function side(t)
        local role = AttackRules.roleEquipe(etat, t) == 'attack' and 'Attaque' or 'Défense'
        return {
            label = ('%s · %s'):format(Config.Teams[t].label, role),
            value = etat.score[t],
            sub = ('%d / %d en vie'):format(AttackRules.compterVivants(etat, t), AttackRules.compter(etat, t)),
            color = Config.Teams[t].color,
        }
    end
    local left, right = side('A'), side('B')
    local subtitle = ('%s  •  %s  •  Premier à %d'):format(zone().name, phaseLabel(), Config.WinRounds)
    if etat.phase == 'live' and etat.chronoEnPause then
        subtitle = subtitle .. '  •  Chrono en pause'
    end
    if etat.phase == 'waiting' then
        subtitle = ('%s  •  En attente : %d / %d joueurs'):format(
            zone().name, AttackRules.nombreJoueurs(etat), Config.PlayersToStart)
    end

    eachPlayer(function(src)
        local t = etat.equipes[src]
        local attack = AttackRules.roleEquipe(etat, t) == 'attack'
        TriggerClientEvent('gf_ui:hud', src, {
            title = etat.manche > 0 and ('Attaque de zone · Manche %d'):format(etat.manche) or 'Attaque de zone',
            subtitle = subtitle,
            timer = remaining,
            badge = {
                text = (attack and 'TU ATTAQUES' or 'TU DÉFENDS')
                    .. (etat.vivants[src] == false and etat.phase == 'live' and ' · ÉLIMINÉ' or ''),
                color = Config.Teams[t].color,
            },
            left = left, right = right,
        })
    end)
end

local function sendScoreboard()
    local rows = {}
    for src, t in pairs(etat.equipes) do
        local st = etat.stats[src] or { kills = 0, deaths = 0 }
        rows[#rows + 1] = {
            cells = { GetPlayerName(src) or '?', Config.Teams[t].label, st.kills, st.deaths,
                etat.vivants[src] and 'En vie' or '—' },
            color = Config.Teams[t].color,
        }
    end
    table.sort(rows, function(a, b) return a.cells[3] > b.cells[3] end)
    local data = {
        title = ('Attaque de zone · %d - %d'):format(etat.score.A, etat.score.B),
        columns = { 'Joueur', 'Équipe', 'Kills', 'Morts', 'État' },
        rows = rows,
    }
    eachPlayer(function(src) TriggerClientEvent('gf_ui:scoreboard', src, data) end)
end

-- participants : joueurs encore présents (avec id) ; partis : joueurs sortis
-- pendant le match (sans id, le nom vient du cache Noms).
local function sendMatchResults(winner, participants, partis, score)
    local players = {}
    for _, p in ipairs(partis) do
        players[#players + 1] = {
            name = Noms[p.src] or '?', team = p.equipe,
            kills = p.kills, deaths = p.deaths,
        }
    end
    for _, p in ipairs(participants) do
        players[#players + 1] = {
            id = p.src, name = GetPlayerName(p.src) or Noms[p.src] or '?', team = p.equipe,
            kills = p.kills, deaths = p.deaths,
        }
    end
    table.sort(players, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        if a.deaths ~= b.deaths then return a.deaths < b.deaths end
        return a.name < b.name
    end)
    -- Journal local : mêmes lignes triées que celles envoyées aux clients.
    local journalRows = {}
    for _, player in ipairs(players) do
        journalRows[#journalRows + 1] = {
            name = player.name, team = player.team, kills = player.kills, deaths = player.deaths,
        }
    end
    TriggerEvent('gf:matchResults', { mode = 'attack', rows = journalRows })
    local best = players[1] and players[1].kills or 0
    local scoreText = ('%s %d - %d %s'):format(
        Config.Teams.A.label, score.A, score.B, Config.Teams.B.label)
    eachPlayer(function(src)
        local rows = {}
        for _, player in ipairs(players) do
            rows[#rows + 1] = {
                name = player.name, team = Config.Teams[player.team].label,
                color = Config.Teams[player.team].color, kills = player.kills,
                deaths = player.deaths, mine = player.id == src,
                best = best > 0 and player.kills == best,
            }
        end
        TriggerClientEvent('gf_ui:match_results', src, {
            won = etat.equipes[src] == winner, score = scoreText, rows = rows,
        })
    end)
end

-- ---------------------------------------------------------------- Effets
-- Le serveur interprète les effets rendus par AttackRules, dans leur ordre.
local executer
executer = function(effets)
    for _, e in ipairs(effets) do
        if e.type == 'phase' then
            -- Journal local des phases : la première manche marque le début du match.
            if e.phase == 'select' and etat.manche == 1 then
                -- Effectif présent au coup d'envoi (équilibrage déjà appliqué par les règles).
                local joueurs = {}
                for src, equipe in pairs(etat.equipes) do
                    joueurs[#joueurs + 1] = { src = src, equipe = equipe }
                end
                TriggerEvent('gf:matchStarted', {
                    mode = 'attack', map = zone().name, joueurs = joueurs,
                })
            end
            TriggerEvent('gf:phase', { mode = 'attack', phase = e.phase, manche = etat.manche })
            -- L'état a déjà été muté par les règles : on diffuse la zone complète.
            sendZoneAll()
        elseif e.type == 'equipe' then
            -- L'équipe est tenue par gf_core : on passe par l'export, qui pose
            -- la table serveur avant d'écrire le state bag.
            core:SetTeam(e.src, e.equipe)
        elseif e.type == 'vivant' then
            if GetPlayerName(e.src) then
                Player(e.src).state:set('gf_alive', e.vivant and true or false, true)
            end
        elseif e.type == 'apparition' then
            if e.mode == 'select' then
                spawnRole(e.src, { vehicle = true, freeze = true, protected = true })
            elseif e.mode == 'place' then
                spawnRole(e.src, { vehicle = true, weapons = true, protected = true })
            elseif e.mode == 'attente' then
                spawnRole(e.src, { protected = true })
            end
            -- Aucun autre mode d'apparition.
        elseif e.type == 'spectateur' then
            toSpectator(e.src)
        elseif e.type == 'menuArmes' then
            openLoadout(e.src)
        elseif e.type == 'fermerMenuArmes' then
            TriggerClientEvent('gf_ui:loadout_close', e.src)
        elseif e.type == 'objets' then
            if e.action == 'reset' then
                resetItems(e.src)
            elseif e.action == 'clear' then
                clearItems(e.src)
            end
        elseif e.type == 'armes' then
            core:GiveWeapons(e.src, core:ResolveSelection(e.src, Choix[e.src]))
        elseif e.type == 'degeler' then
            core:Freeze(e.src, false)
        elseif e.type == 'protection' then
            core:SetProtected(e.src, e.protege)
        elseif e.type == 'notifier' then
            if e.modele == 'rejoint' then
                core:Notify(e.src, ("Tu rejoins l'%s. Tape /lobby pour quitter."):format(Config.Teams[e.equipe].label))
            elseif e.modele == 'equilibrage' then
                -- Une escouade entière est déplacée : le message s'adresse au groupe.
                if e.escouade then
                    core:Notify(e.src, ("Équilibrage : ton escouade passe dans l'%s"):format(Config.Teams[e.equipe].label))
                else
                    core:Notify(e.src, ("Équilibrage : tu passes dans l'%s"):format(Config.Teams[e.equipe].label))
                end
            end
        elseif e.type == 'annonce' then
            if e.modele == 'debutManche' then
                local roleText = e.role == 'attack'
                    and ('Tu ATTAQUES : ' .. zone().name) or ('Tu DÉFENDS : ' .. zone().name)
                if e.changementDeCamp then
                    announce(e.src, 'CHANGEMENT DE CAMP', ('Manche %d  ·  %s'):format(e.manche, roleText), e.dureeMs)
                else
                    announce(e.src, ('Manche %d'):format(e.manche), roleText, e.dureeMs)
                end
            elseif e.modele == 'debutMancheTest' then
                announceAll(('Manche %d (test)'):format(e.manche),
                    'Une équipe est vide : la manche se termine au chrono', e.dureeMs)
            elseif e.modele == 'placement' then
                announce(e.src, 'Placement', e.role == 'attack'
                    and ('Zone fermée pendant %d s : prépare ton attaque'):format(e.secondes)
                    or ('%d s pour te placer dans la zone'):format(e.secondes), e.dureeMs)
            elseif e.modele == 'go' then
                announceAll('GO !', 'La zone est ouverte : à l\'attaque !', e.dureeMs)
            elseif e.modele == 'elimine' then
                announce(e.src, 'Éliminé', 'Tu regardes tes alliés (clic gauche / droit pour changer)', e.dureeMs)
            elseif e.modele == 'mancheEnCours' then
                announce(e.src, 'Manche en cours', 'Tu joueras dès la prochaine manche', e.dureeMs)
            end
            -- Pas de modèle 'matchArrete' : c'est l'effet matchArrete qui parle.
        elseif e.type == 'finManche' then
            -- Journal local de la fin de manche (même en cas de fin de match).
            TriggerEvent('gf:roundEnded', {
                mode = 'attack', manche = etat.manche, gagnant = e.gagnant, raison = e.raison,
                score = { A = e.score.A, B = e.score.B }, map = zone().name,
            })
            if not e.matchOver then
                local scoreText = ('%s %d - %d %s'):format(
                    Config.Teams.A.label, e.score.A, e.score.B, Config.Teams.B.label)
                eachPlayer(function(src)
                    local won = etat.equipes[src] == e.gagnant
                    announce(src, won and 'MANCHE GAGNÉE' or 'MANCHE PERDUE',
                        e.raison .. '  ·  ' .. scoreText, e.dureeMs)
                end)
            end
        elseif e.type == 'finMatch' then
            local participants = {}
            for _, p in ipairs(e.participants) do
                participants[#participants + 1] = { src = p.src, won = p.equipe == e.gagnant }
            end
            TriggerEvent('gf:matchEnded', {
                mode = 'attack',
                map = zone().name,
                participants = participants,
                score = { A = e.score.A, B = e.score.B },
            })
            sendMatchResults(e.gagnant, e.participants, e.partis, e.score)
        elseif e.type == 'retourLobby' then
            -- L'état a déjà été réinitialisé par les règles : on reproduit
            -- l'ancien gf:modeLeft avant de renvoyer le joueur au lobby.
            clearItems(e.src)
            TriggerClientEvent('gf_ui:match_results', e.src, nil)
            if GetPlayerName(e.src) then
                core:SetTeam(e.src, nil)
                Player(e.src).state:set('gf_alive', nil, true)
                TriggerClientEvent('gf_ui:loadout_close', e.src)
                TriggerClientEvent('gf_attack:clear', e.src)
            end
            core:SetMode(e.src, 'lobby')
        elseif e.type == 'chargerCarte' then
            if e.mode == 'recharger' then
                loadMap(zoneIndex)
            elseif e.mode == 'suivante' then
                loadMap(zoneIndex + 1)
            end
        elseif e.type == 'effacerResultats' then
            TriggerClientEvent('gf_ui:match_results', e.src, nil)
        elseif e.type == 'nettoyerJoueur' then
            if GetPlayerName(e.src) then
                core:SetTeam(e.src, nil)
                Player(e.src).state:set('gf_alive', nil, true)
                TriggerClientEvent('gf_ui:loadout_close', e.src)
                TriggerClientEvent('gf_attack:clear', e.src)
            end
        elseif e.type == 'recompenseKevlar' then
            local inv = Items[e.src]
            if inv and etat.vivants[e.src] and inv.kevlar < Config.MaxKevlars then
                inv.kevlar = math.min(Config.MaxKevlars, inv.kevlar + Config.KevlarPerKill)
                sendItems(e.src)
            end
        elseif e.type == 'statistiquesKill' then
            TriggerEvent('gf:modeKill', { mode = 'attack', victim = e.victime, killer = e.tueur or false })
        elseif e.type == 'spectateurDiffere' then
            local src, delai = e.src, e.delaiMs
            SetTimeout(delai, function()
                if etat.equipes[src] and not etat.vivants[src] then toSpectator(src) end
            end)
        elseif e.type == 'placementDiffere' then
            local src, delai = e.src, e.delaiMs
            SetTimeout(delai, function()
                if etat.equipes[src] then executer(AttackRules.placer(etat, src)) end
            end)
        elseif e.type == 'zone' then
            sendZone(e.src)
        elseif e.type == 'classement' then
            classementSale = true
        elseif e.type == 'matchArrete' then
            announceAll('Match arrêté', 'Par un administrateur', 4000)
            TriggerEvent('gf:matchAborted', { mode = 'attack' }) -- journal local de l'arrêt
        end
    end
end

-- ---------------------------------------------------------------- Boucle principale
CreateThread(function()
    while true do
        Wait(1000)
        local t = GetGameTimer()
        local dansZone = etat.phase == 'live' and attackerInZone() or false
        executer(AttackRules.tic(etat, t, dansZone))
        sendHud()
        if classementSale then
            classementSale = false
            sendScoreboard()
        end
    end
end)

-- ---------------------------------------------------------------- Événements gf_core
-- Le menu d'armes (gf_ui) envoie le choix ; gf_core le valide (armes possédées)
RegisterNetEvent('gf:loadoutChosen', function(ids)
    local src = source
    if not etat.equipes[src] or etat.phase ~= 'select' then return end
    Choix[src] = core:ResolveSelection(src, ids)
end)

AddEventHandler('playerDropped', function()
    local src = source
    Choix[src] = nil
    Items[src], Using[src] = nil, nil
    -- Noms est volontairement conservé pour le classement final.
end)

AddEventHandler('gf:modeJoined', function(src, mode)
    if mode ~= 'attack' then return end
    Noms[src] = GetPlayerName(src) or '?'
    executer(AttackRules.arrivee(etat, src))
end)

AddEventHandler('gf:modeLeft', function(src, mode)
    if mode ~= 'attack' or not etat.equipes[src] then return end
    executer(AttackRules.depart(etat, src, GetGameTimer()))
end)

AddEventHandler('gf:playerKilled', function(victim, killer, weapon, mode)
    if mode ~= 'attack' or not etat.equipes[victim] then return end
    executer(AttackRules.mort(etat, victim, killer, GetGameTimer()))
end)

-- Si gf_core redémarre, ses joueurs repartent au lobby : on repart de zéro
AddEventHandler('onResourceStop', function(res)
    if res == 'gf_core' then AttackRules.reinitialiser(etat) end
end)

-- Si gf_attack (re)démarre alors que des joueurs étaient dans le mode, on les renvoie au lobby
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if core:GetMode(src) == 'attack' then core:SetMode(src, 'lobby') end
    end
end)

-- ---------------------------------------------------------------- Exports et commandes
exports('CanJoin', function()
    return AttackRules.peutRejoindre(etat)
end)

-- Enregistre les escouades ([src] = clé de groupe) auprès des règles.
exports('RegisterSquads', function(escouades)
    if type(escouades) ~= 'table' then return false end
    executer(AttackRules.definirGroupes(etat, escouades))
    return true
end)

-- Cartes proposées au vote du lobby, dans l'ordre de la rotation.
exports('GetMapChoices', function()
    local choices = {}
    for i, m in ipairs(mapList()) do
        choices[#choices + 1] = {
            id = choiceId(m, i),
            name = tostring(m.name or ('Zone ' .. i)),
        }
    end
    return choices
end)

-- Choix de la carte du prochain match, uniquement en attente. Le rechargement
-- de la carte au début du match jouera cette carte et reprendra la rotation.
exports('SetNextMap', function(id)
    if type(id) ~= 'string' or etat.phase ~= 'waiting' then return false end
    for i, m in ipairs(mapList()) do
        if choiceId(m, i) == id then
            loadMap(i)
            if next(etat.equipes) ~= nil then
                executer(AttackRules.allerEnAttente(etat))
            end
            return true
        end
    end
    return false
end)

local function reply(src, msg)
    if src == 0 then print('[gf_attack] ' .. msg) else core:Notify(src, msg) end
end

-- /startround : force le lancement pour l'admin ET toute la file du lobby, sans seuil
-- La file du lobby part en premier : si l'admin y est avec son escouade, il
-- entre avec elle (même équipe) au lieu de partir seul avant elle. Les joueurs
-- de la file arrivent après le délai de lancement du lobby (700 ms) : l'admin
-- n'entre seul qu'ensuite, s'il n'est pas déjà dans le mode, puis la manche
-- démarre. Sans joueur dans la file : entrée de l'admin puis manche immédiate.
local function entrerAdmin(src)
    if src and src > 0 and not etat.equipes[src]
        and AttackRules.nombreJoueurs(etat) < Config.MaxPlayers then
        core:SetMode(src, 'attack')
    end
end

local function startTestRound(src)
    if not AttackRules.estOuvert(etat) then return false, 'Un match est déjà en cours.' end
    local places = Config.MaxPlayers - AttackRules.nombreJoueurs(etat)
    local lances = 0
    if places > 0 and GetResourceState('gf_lobby') == 'started' then
        local ok, n = pcall(function() return exports.gf_lobby:ForceLaunchQueue(places) end)
        lances = (ok and type(n) == 'number' and n > 0) and n or 0
    end
    if lances > 0 then
        SetTimeout(2500, function()
            if not AttackRules.estOuvert(etat) then return end
            entrerAdmin(src)
            if next(etat.equipes) ~= nil then
                executer(AttackRules.debutTest(etat, GetGameTimer()))
            end
        end)
        return true, ('Lancement forcé : %d joueur(s) de la file rejoignent la partie.'):format(lances)
    end
    entrerAdmin(src)
    if next(etat.equipes) == nil then return false, 'Aucun joueur dans le mode Attaque.' end
    executer(AttackRules.debutTest(etat, GetGameTimer()))
    return true
end
exports('StartTestRound', startTestRound)

-- /startround : force le lancement pour l'admin ET toute la file du lobby, sans seuil
RegisterCommand('startround', function(src)
    if not core:IsAdmin(src) then
        core:Notify(src, ADMIN_REQUIS)
        return
    end
    local ok, msg = startTestRound(src)
    if not ok then
        reply(src, msg)
    else
        if msg then reply(src, msg) end
        if GetResourceState('gf_admin') == 'started' then
            pcall(function() exports.gf_admin:LogAction(src, 'startround', nil, 'mode=attack') end)
        end
    end
end, false)

-- /endmatch : arrête le match et remet les scores à zéro
RegisterCommand('endmatch', function(src)
    if not core:IsAdmin(src) then
        core:Notify(src, ADMIN_REQUIS)
        return
    end
    -- Les effets font les remises à zéro, l'annonce et les apparitions.
    executer(AttackRules.finMatch(etat))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'endmatch', nil, 'mode=attack') end)
    end
end, false)

-- /nextzone : passe à la zone suivante (en attente uniquement)
RegisterCommand('nextzone', function(src)
    if not core:IsAdmin(src) then
        core:Notify(src, ADMIN_REQUIS)
        return
    end
    if etat.phase ~= 'waiting' then return reply(src, 'Utilise /endmatch avant de changer de zone.') end
    loadMap(zoneIndex + 1)
    executer(AttackRules.allerEnAttente(etat))
    reply(src, 'Zone : ' .. zone().name)
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'nextzone', nil, 'zone=' .. zone().name) end)
    end
end, false)

-- /setteam [id] [A|B]
RegisterCommand('setteam', function(src, args)
    if not core:IsAdmin(src) then
        core:Notify(src, ADMIN_REQUIS)
        return
    end
    local target, t = tonumber(args[1]), (args[2] or ''):upper()
    if not target or (t ~= 'A' and t ~= 'B') or not etat.equipes[target] then
        return reply(src, 'Utilisation : /setteam [id] [A|B] (le joueur doit être dans le mode Attaque)')
    end
    executer(AttackRules.changerEquipe(etat, target, t, GetGameTimer()))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'setteam', target, 'equipe=' .. t) end)
    end
end, false)

-- Une map a été créée / modifiée / supprimée avec /editor
AddEventHandler('gf_maps:updated', function(kind)
    if kind ~= 'attack' then return end
    if etat.phase == 'waiting' then
        loadMap(zoneIndex)
        executer(AttackRules.allerEnAttente(etat))
    end
end)
