-- =============================================================================
--  gf_journal - SERVEUR
--  Écoute les événements de match, les met en tampon et les écrit par lots dans
--  MariaDB (table gf_match_events, voir gf_db/migrations/0002_*.sql).
--
--  Aucun événement n'est émis ni diffusé aux clients : cette ressource est un
--  simple observatoire. Les identifiants ne sont stockés que dans la colonne
--  `donnees` (JSON) et ne sont jamais écrits dans un log console.
-- =============================================================================

local PLATEAU_LIGNES = 20000
local TAILLE_LOT = 200
local MAX_TENTATIVES = 3

local tampon = Journal.nouveau()
local idsMatch = {}        -- id de match courant par mode
local manches = {}         -- numéro de manche courant par mode
local compteurMatch = 0
local lotEnAttente = nil
local tentatives = 0
local perduesDepuisLog = 0
local dernierLogPlein = 0

-- ---------------------------------------------------------------------------
--  Joueurs (aucune IP, jamais de licence dans les logs)
-- ---------------------------------------------------------------------------

--- Identifiant stable : license en priorité, sinon fivem/steam/discord.
--- Protégé par pcall : une ressource tierce ne peut pas faire planter un handler.
local function identifierOf(src)
    local ok, identifiants = pcall(GetPlayerIdentifiers, src)
    if not ok or type(identifiants) ~= 'table' then return nil end

    local fallback
    for _, id in ipairs(identifiants) do
        if type(id) == 'string' then
            if id:find('^license:') then return id end
            if not fallback and (id:find('^fivem:') or id:find('^steam:') or id:find('^discord:')) then
                fallback = id
            end
        end
    end
    return fallback
end

--- Décrit un joueur pour la colonne `donnees` (licence incluse, mais en base).
local function joueur(src)
    if type(src) ~= 'number' then return false end
    local ok, nom = pcall(GetPlayerName, src)
    return {
        src = src,
        id = identifierOf(src),
        nom = (ok and nom or nil) or '?',
    }
end

local function equipeDe(src)
    if type(src) ~= 'number' then return nil end
    local ok, equipe = pcall(function()
        local joueurCoteServeur = Player(src)
        return joueurCoteServeur and joueurCoteServeur.state.gf_team or nil
    end)
    if not ok then return nil end
    return equipe
end

local function modeDe(src)
    local ok, mode = pcall(function()
        return exports.gf_core:GetMode(src)
    end)
    if not ok then return nil end
    return mode
end

-- ---------------------------------------------------------------------------
--  Ajout dans le tampon
-- ---------------------------------------------------------------------------

local function logPlein()
    local maintenant = GetGameTimer()
    if maintenant - dernierLogPlein < 60000 then return end
    dernierLogPlein = maintenant
    if perduesDepuisLog <= 0 then return end
    print(('[gf_journal] tampon plein : %d lignes perdues'):format(perduesDepuisLog))
    perduesDepuisLog = 0
end

--- Ajoute une ligne au tampon, en appliquant le plafond et en journalisant les pertes.
local function ajouter(typeLigne, mode, donnees, manche)
    if type(mode) ~= 'string' or mode == '' then return end

    local ligne = {
        match_id = idsMatch[mode],
        mode = mode,
        manche = manche ~= nil and manche or manches[mode],
        t_ms = GetGameTimer(),
        type = typeLigne,
        donnees = donnees or {},
    }
    Journal.ajouter(tampon, ligne)

    while #tampon.lignes > PLATEAU_LIGNES do
        table.remove(tampon.lignes, 1)
        tampon.perdues = (tampon.perdues or 0) + 1
        perduesDepuisLog = perduesDepuisLog + 1
    end
    logPlein()
end

-- ---------------------------------------------------------------------------
--  Écriture par lots
-- ---------------------------------------------------------------------------

--- Construit une requête multi-lignes entièrement paramétrée.
--- Seuls les `?`, le mot-clé `NULL` et les noms de colonnes sont concaténés ;
--- aucune valeur utilisateur n'entre dans le SQL.
local function construireInsert(lot)
    local colonnes = '(match_id, mode, manche, t_ms, type, donnees)'
    local groupes = {}
    local params = {}

    for _, ligne in ipairs(lot) do
        local valeurs = {}
        -- match_id : NULL autorisé en base.
        if ligne.match_id ~= nil then
            valeurs[#valeurs + 1] = '?'
            params[#params + 1] = ligne.match_id
        else
            valeurs[#valeurs + 1] = 'NULL'
        end
        -- mode et type : NOT NULL en base, donc toujours paramétrés (jamais NULL).
        valeurs[#valeurs + 1] = '?'
        params[#params + 1] = ligne.mode
        if ligne.manche ~= nil then
            valeurs[#valeurs + 1] = '?'
            params[#params + 1] = ligne.manche
        else
            valeurs[#valeurs + 1] = 'NULL'
        end
        valeurs[#valeurs + 1] = '?'
        params[#params + 1] = ligne.t_ms
        valeurs[#valeurs + 1] = '?'
        params[#params + 1] = ligne.type
        valeurs[#valeurs + 1] = '?'
        local ok, json = pcall(Journal.encoderJson, ligne.donnees or {})
        params[#params + 1] = ok and json or '{}'

        groupes[#groupes + 1] = '(' .. table.concat(valeurs, ', ') .. ')'
    end

    local requete = ('INSERT INTO gf_match_events %s VALUES %s'):format(
        colonnes, table.concat(groupes, ', '))
    return requete, params
end

--- Tente d'écrire un lot. Retourne true si le lot peut être oublié.
local function ecrireLot(lot)
    if type(lot) ~= 'table' or #lot == 0 then return true end

    local requete, params = construireInsert(lot)
    local ok, err = pcall(function()
        MySQL.insert.await(requete, params)
    end)
    if ok then
        tentatives = 0
        return true
    end

    -- Message seul : ni les données, ni un identifiant, ni la requête.
    print(('[gf_journal] ERREUR %s'):format(tostring(err)))
    return false
end

local function abandonnerLot(lot)
    local pertes = type(lot) == 'table' and #lot or 0
    if pertes > 0 then
        tampon.perdues = (tampon.perdues or 0) + pertes
        perduesDepuisLog = perduesDepuisLog + pertes
        print(('[gf_journal] lot abandonné après %d tentatives : %d lignes perdues'):format(
            MAX_TENTATIVES, pertes))
        logPlein()
    end
    tentatives = 0
end

local function traiterLot()
    local okPret, pret = pcall(function()
        return exports.gf_db:Pret()
    end)
    if not okPret or not pret then return end

    local lot = lotEnAttente
    if lot then
        if ecrireLot(lot) then
            lotEnAttente = nil
        else
            tentatives = tentatives + 1
            if tentatives >= MAX_TENTATIVES then
                abandonnerLot(lot)
                lotEnAttente = nil
            end
        end
        return
    end

    lot = Journal.extraireLot(tampon, TAILLE_LOT)
    if type(lot) ~= 'table' or #lot == 0 then return end

    lotEnAttente = lot
    tentatives = 1
    if ecrireLot(lot) then
        lotEnAttente = nil
    elseif tentatives >= MAX_TENTATIVES then
        abandonnerLot(lot)
        lotEnAttente = nil
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        local ok, err = pcall(traiterLot)
        if not ok then
            print(('[gf_journal] ERREUR %s'):format(tostring(err)))
        end
    end
end)

-- Dernier passage best effort à l'arrêt de la ressource.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    pcall(traiterLot)
end)

-- ---------------------------------------------------------------------------
--  Événements écoutés (jamais TriggerEvent / TriggerClientEvent ici)
-- ---------------------------------------------------------------------------

AddEventHandler('gf:hit', function(data)
    if type(data) ~= 'table' then return end
    local mode = modeDe(data.sender)
    if type(mode) ~= 'string' or mode == '' then return end

    ajouter('touche', mode, {
        tireur = joueur(data.sender) or false,
        victime = joueur(data.victim) or false,
        arme = data.weapon,
        degats = tonumber(data.damage) or 0,
        willKill = data.willKill and true or false,
        composant = data.component,
        accepte = data.accepted and true or false,
        raison = tostring(data.reason or '?'),
    }, nil)
end)

AddEventHandler('gf:matchStarted', function(data)
    if type(data) ~= 'table' then return end
    local mode = data.mode
    if type(mode) ~= 'string' or mode == '' then return end

    compteurMatch = compteurMatch + 1
    idsMatch[mode] = Journal.nouvelIdMatch(mode, os.time(), compteurMatch)
    manches[mode] = 0
    -- Effectif au coup d'envoi : les joueurs restés à 0 kill / 0 mort sans ligne
    -- rattachée au match seraient sinon absents du recalcul.
    local listeJoueurs = {}
    for _, entree in ipairs(type(data.joueurs) == 'table' and data.joueurs or {}) do
        if type(entree) == 'table' and type(entree.src) == 'number' then
            local fiche = joueur(entree.src)
            if fiche then
                listeJoueurs[#listeJoueurs + 1] = {
                    joueur = fiche,
                    equipe = entree.equipe,
                }
            end
        end
    end
    ajouter('debut_match', mode, { map = data.map, joueurs = listeJoueurs }, 0)
end)

AddEventHandler('gf:phase', function(data)
    if type(data) ~= 'table' then return end
    local mode = data.mode
    if type(mode) ~= 'string' or mode == '' then return end

    if data.manche ~= nil then manches[mode] = data.manche end
    ajouter('phase', mode, { phase = data.phase, manche = data.manche }, nil)
end)

AddEventHandler('gf:roundEnded', function(data)
    if type(data) ~= 'table' then return end
    local mode = data.mode
    if type(mode) ~= 'string' or mode == '' then return end

    ajouter('fin_manche', mode, {
        manche = data.manche,
        gagnant = data.gagnant,
        raison = data.raison,
        score = data.score,
        map = data.map,
    }, nil)
end)

AddEventHandler('gf:matchResults', function(data)
    if type(data) ~= 'table' then return end
    local mode = data.mode
    if type(mode) ~= 'string' or mode == '' then return end

    ajouter('resultats', mode, { rows = data.rows or {} }, nil)
    idsMatch[mode] = nil
    manches[mode] = nil
end)

AddEventHandler('gf:matchAborted', function(data)
    if type(data) ~= 'table' then return end
    local mode = data.mode
    if type(mode) ~= 'string' or mode == '' then return end

    ajouter('abandon', mode, {}, nil)
    idsMatch[mode] = nil
    manches[mode] = nil
end)

AddEventHandler('gf:matchEnded', function(data)
    if type(data) ~= 'table' then return end
    local mode = data.mode
    if type(mode) ~= 'string' or mode == '' then return end

    ajouter('fin_match', mode, {
        map = data.map,
        score = data.score,
        participants = data.participants,
    }, nil)
end)

-- gf_journal démarre avant gf_attack : l'équipe n'est pas encore posée quand cet
-- handler tourne. On capture joueur/mode tout de suite et on diffère la ligne au
-- tick suivant, où gf_attack a eu le temps d'appliquer son propre gf:modeJoined.
AddEventHandler('gf:modeJoined', function(src, mode)
    if type(mode) ~= 'string' or mode == '' then return end
    local joueurArrivee = joueur(src)
    SetTimeout(0, function()
        pcall(ajouter, 'arrivee', mode, {
            joueur = joueurArrivee or false,
            equipe = equipeDe(src),
        }, nil)
    end)
end)

AddEventHandler('gf:modeLeft', function(src, mode)
    if type(mode) ~= 'string' or mode == '' then return end
    ajouter('depart', mode, { joueur = joueur(src) or false, equipe = equipeDe(src) }, nil)
end)

AddEventHandler('gf:playerKilled', function(victim, killer, weapon, mode)
    if type(mode) ~= 'string' or mode == '' then return end
    ajouter('mort', mode, {
        victime = joueur(victim) or false,
        tueur = killer and joueur(killer) or false,
        arme = weapon,
    }, nil)
end)

AddEventHandler('gf:modeKill', function(data)
    if type(data) ~= 'table' then return end
    local mode = data.mode
    if type(mode) ~= 'string' or mode == '' then return end

    ajouter('kill', mode, {
        victime = joueur(data.victim) or false,
        tueur = data.killer and joueur(data.killer) or false,
        equipe_victime = equipeDe(data.victim),
        equipe_tueur = data.killer and equipeDe(data.killer) or nil,
    }, nil)
end)
