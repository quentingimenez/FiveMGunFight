-- =============================================================================
--  gf_menu - MENU_STATE (module pur, sans native ni I/O)
--  Formatage et construction de l'état affiché. Le temps arrive en paramètre
--  (GetGameTimer() côté appelant) pour que le module reste testable.
-- =============================================================================

GFMenuState = {}

local SECONDES_PAR_MINUTE = 60
local MINUTES_PAR_HEURE = 60
local HEURES_PAR_JOUR = 24
local MINUTES_PAR_JOUR = HEURES_PAR_JOUR * MINUTES_PAR_HEURE
local SECONDES_PAR_HEURE = MINUTES_PAR_HEURE * SECONDES_PAR_MINUTE
local SECONDES_PAR_JOUR = HEURES_PAR_JOUR * SECONDES_PAR_HEURE
local MS_PAR_SECONDE = 1000
local TIRET = '—'

local function estNombreFini(valeur)
    return type(valeur) == 'number'
        and valeur == valeur
        and valeur ~= math.huge
        and valeur ~= -math.huge
end

local function nombreOuZero(valeur)
    if estNombreFini(valeur) then return valeur end
    return 0
end

--- Ratio kills/morts à deux décimales. Sans mort, le nombre de kills est
--- affiché tel quel (0 mort = ratio non défini, on ne divise pas par zéro).
--- Une entrée non numérique donne le tiret.
function GFMenuState.formatKd(kills, deaths)
    if not estNombreFini(kills) or not estNombreFini(deaths) then return TIRET end
    if deaths <= 0 then return string.format('%.2f', kills) end
    return string.format('%.2f', kills / deaths)
end

--- Durée de session : minutes, puis heures et minutes, puis jours et heures.
--- Une valeur négative, NaN ou infinie donne le tiret.
function GFMenuState.formatDuration(secondes)
    if not estNombreFini(secondes) or secondes < 0 then return TIRET end

    local minutes = math.floor(secondes / SECONDES_PAR_MINUTE)
    if minutes < MINUTES_PAR_HEURE then
        return ('%d min'):format(minutes)
    end

    if minutes < MINUTES_PAR_JOUR then
        local heures = math.floor(secondes / SECONDES_PAR_HEURE)
        local resteMinutes = math.floor((secondes % SECONDES_PAR_HEURE) / SECONDES_PAR_MINUTE)
        return ('%d h %02d'):format(heures, resteMinutes)
    end

    local jours = math.floor(secondes / SECONDES_PAR_JOUR)
    local resteHeures = math.floor((secondes % SECONDES_PAR_JOUR) / SECONDES_PAR_HEURE)
    return ('%d j %d h'):format(jours, resteHeures)
end

--- Libellé du mode : table Config.ModeLabels, HORS PARTIE si le mode est
--- absent ou vide, EN PARTIE pour un mode non répertorié.
function GFMenuState.modeLabel(mode)
    if mode == nil or mode == '' then return Config.ModeLabelIdle end
    if type(mode) == 'string' and type(Config.ModeLabels) == 'table' then
        local libelle = Config.ModeLabels[mode]
        if libelle then return libelle end
    end
    return Config.ModeLabelFallback
end

--- Cooldown à sens unique, sans horloge propre : `maintenant` et l'état
--- mutable sont fournis par l'appelant. `lastAt` n'est écrit que si l'action
--- est autorisée, pour ne pas repousser l'échéance à chaque refus.
function GFMenuState.cooldown(session, maintenant, intervalle_ms)
    if type(session) ~= 'table' then return false end
    if not estNombreFini(maintenant) or not estNombreFini(intervalle_ms) then return false end
    if intervalle_ms < 0 then return false end

    local dernier = session.lastAt
    if dernier ~= nil and not estNombreFini(dernier) then return false end
    if maintenant - (dernier or -math.huge) < intervalle_ms then return false end

    session.lastAt = maintenant
    return true
end

--- Construit l'état complet de la NUI sans effet de bord. Tous les champs de
--- `ctx` sont facultatifs : un champ manquant donne une valeur neutre.
function GFMenuState.buildState(ctx)
    local contexte = type(ctx) == 'table' and ctx or {}
    local stats = type(contexte.stats) == 'table' and contexte.stats or nil

    local kills, deaths, matches, wins = 0, 0, 0, 0
    local memberSince, kd = TIRET, TIRET
    if stats then
        kills = nombreOuZero(stats.kills)
        deaths = nombreOuZero(stats.deaths)
        matches = nombreOuZero(stats.matches)
        wins = nombreOuZero(stats.wins)
        memberSince = stats.memberSince or TIRET
        kd = GFMenuState.formatKd(kills, deaths)
    end

    local maintenant = contexte.now
    local arrivee = contexte.joinedAt
    local secondesDeSession = nil
    if estNombreFini(maintenant) and estNombreFini(arrivee) then
        secondesDeSession = (maintenant - arrivee) / MS_PAR_SECONDE
    end

    return {
        build = contexte.build or Config.BuildFallback,
        server = { name = Config.ServerName },
        online = contexte.online,
        maxPlayers = contexte.maxPlayers,
        me = {
            id = contexte.id,
            name = contexte.name or TIRET,
            mode = contexte.mode,
            modeLabel = GFMenuState.modeLabel(contexte.mode),
            memberSince = memberSince,
        },
        statsAvailable = stats ~= nil,
        stats = {
            kills = kills,
            deaths = deaths,
            matches = matches,
            wins = wins,
            kd = kd,
            session = GFMenuState.formatDuration(secondesDeSession),
        },
        rules = Config.Rules,
        discord = { url = Config.DiscordUrl },
        features = Config.Features,
    }
end
