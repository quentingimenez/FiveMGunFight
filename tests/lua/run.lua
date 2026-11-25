-- =============================================================================
--  Tests unitaires des modules serveur purs de gf_core.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/run.lua
--  Aucune native FiveM n'est appelée : les modules testés reçoivent leurs
--  dépendances en paramètre.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/run%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()
local MODULES = RACINE .. '/server-data/resources/[gunfight]/gf_core/'

dofile(MODULES .. 'validation.lua')
dofile(MODULES .. 'rate_limit.lua')

local reussis, echecs = 0, 0

local function verifier(nom, fonction)
    local ok, erreur = pcall(fonction)
    if ok then
        reussis = reussis + 1
        print(('ok      %s'):format(nom))
    else
        echecs = echecs + 1
        print(('ECHEC   %s\n        %s'):format(nom, tostring(erreur)))
    end
end

local function egal(attendu, obtenu, message)
    if attendu ~= obtenu then
        error(('%s : attendu %s, obtenu %s'):format(message, tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(valeur, message)
    if not valeur then error(message, 2) end
end

local function dependancesVehicule(surcharges)
    local deps = {
        entityFromNetId = function() return 11 end,
        entityExists = function() return true end,
        entityType = function() return 2 end,
        entityOwner = function() return 42 end,
        entityCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end,
        playerCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end,
        maxDistance = 50.0,
    }
    for cle, valeur in pairs(surcharges or {}) do
        deps[cle] = valeur
    end
    return deps
end

-- ---------------------------------------------------------------- netId
verifier('netId : entiers positifs acceptés', function()
    egal(42, Validation.normaliserNetId(42), 'entier')
    egal(7, Validation.normaliserNetId(7.0), 'flottant entier')
    egal(65535, Validation.normaliserNetId('65535'), 'chaîne numérique')
end)

verifier('netId : valeurs invalides refusées', function()
    local invalides = { 0, -1, 12.5, 'abc', '12a', '', math.huge, -math.huge, 0 / 0, true, {} }
    for _, valeur in ipairs(invalides) do
        egal(nil, Validation.normaliserNetId(valeur), 'valeur ' .. tostring(valeur))
    end
    egal(nil, Validation.normaliserNetId(nil), 'nil')
end)

-- ---------------------------------------------------------------- distance
verifier(
    'distance : triangle 3-4-5',
    function() egal(5.0, Validation.distance({ x = 0, y = 0, z = 0 }, { x = 3, y = 4, z = 0 }), 'distance') end
)

verifier('distance : positions invalides', function()
    egal(nil, Validation.distance(nil, { x = 0, y = 0, z = 0 }), 'nil')
    egal(nil, Validation.distance({ x = 0, y = 0 }, { x = 0, y = 0, z = 0 }), 'z manquant')
    egal(nil, Validation.distance({ x = 0 / 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }), 'NaN')
end)

-- ---------------------------------------------------------------- véhicule
verifier('véhicule : cas valide', function()
    local ok, raison, id = Validation.verifierVehicule(12, 42, dependancesVehicule())
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('ok', raison, 'raison')
    egal(12, id, 'netId normalisé')
end)

verifier('véhicule : netId invalide refusé', function()
    local ok, raison = Validation.verifierVehicule('abc', 42, dependancesVehicule())
    egal(false, ok, 'ok')
    egal('netId', raison, 'raison')
end)

verifier('véhicule : entité inexistante refusée', function()
    local deps = dependancesVehicule({ entityExists = function() return false end })
    local ok, raison = Validation.verifierVehicule(12, 42, deps)
    egal(false, ok, 'ok')
    egal('introuvable', raison, 'raison')
end)

verifier('véhicule : mauvais type refusé', function()
    local deps = dependancesVehicule({ entityType = function() return 1 end })
    local ok, raison = Validation.verifierVehicule(12, 42, deps)
    egal(false, ok, 'ok')
    egal('type', raison, 'raison')
end)

verifier('véhicule : mauvais propriétaire refusé', function()
    local deps = dependancesVehicule({ entityOwner = function() return 43 end })
    local ok, raison = Validation.verifierVehicule(12, 42, deps)
    egal(false, ok, 'ok')
    egal('proprietaire', raison, 'raison')
end)

verifier('véhicule : distance trop grande refusée', function()
    local deps = dependancesVehicule({
        entityCoords = function() return { x = 51.0, y = 0.0, z = 0.0 } end,
    })
    local ok, raison = Validation.verifierVehicule(12, 42, deps)
    egal(false, ok, 'ok')
    egal('distance', raison, 'raison')
end)

verifier('véhicule : distance limite acceptée', function()
    local deps = dependancesVehicule({
        entityCoords = function() return { x = 50.0, y = 0.0, z = 0.0 } end,
    })
    local ok = Validation.verifierVehicule(12, 42, deps)
    vrai(ok, '50 m doit être accepté')
end)

verifier('véhicule : position indisponible refusée', function()
    local deps = dependancesVehicule({ playerCoords = function() return nil end })
    local ok, raison = Validation.verifierVehicule(12, 42, deps)
    egal(false, ok, 'ok')
    egal('position', raison, 'raison')
end)

verifier('véhicule : distance maximale invalide refusée', function()
    local deps = dependancesVehicule({ maxDistance = 0 / 0 })
    local ok, raison = Validation.verifierVehicule(12, 42, deps)
    egal(false, ok, 'ok')
    egal('distance', raison, 'raison')
end)

-- ---------------------------------------------------------------- rate-limit
verifier('rate-limit : 2 autorisés puis refus, reset après la fenêtre', function()
    local etat = {}
    vrai(RateLimit.autoriser(etat, 'vehicule', 2, 1000, 0), '1re action')
    vrai(RateLimit.autoriser(etat, 'vehicule', 2, 1000, 100), '2e action')
    egal(false, RateLimit.autoriser(etat, 'vehicule', 2, 1000, 999), '3e avant la fenêtre')
    vrai(RateLimit.autoriser(etat, 'vehicule', 2, 1000, 1000), '1re action de 0 expirée')
    -- La fenêtre glisse : l'action de 100 ms est encore comptée à 1001 ms.
    egal(false, RateLimit.autoriser(etat, 'vehicule', 2, 1000, 1001), 'fenêtre glissante')
end)

verifier('rate-limit : clés indépendantes', function()
    local etat = {}
    vrai(RateLimit.autoriser(etat, 'a', 1, 1000, 0), 'a')
    egal(false, RateLimit.autoriser(etat, 'a', 1, 1000, 1), 'a bloqué')
    vrai(RateLimit.autoriser(etat, 'b', 1, 1000, 1), 'b indépendant')
end)

verifier('rate-limit : oubli de la clé', function()
    local etat = {}
    vrai(RateLimit.autoriser(etat, 'a', 1, 1000, 0), '1re')
    egal(false, RateLimit.autoriser(etat, 'a', 1, 1000, 1), 'bloqué')
    RateLimit.oublier(etat, 'a')
    vrai(RateLimit.autoriser(etat, 'a', 1, 1000, 2), 'après oubli')
end)

-- ---------------------------------------------------------------- kills
verifier('kill : dégât récent crédité', function()
    local src, arme = Validation.tueurCreditable({ src = 7, at = 5000, weapon = 42 }, 9000, 10000, true, 8)
    egal(7, src, 'tueur')
    egal(42, arme, 'arme')
end)

verifier('kill : dégât ancien refusé', function()
    local src = Validation.tueurCreditable({ src = 7, at = 0, weapon = 42 }, 10000, 10000, true, 8)
    egal(nil, src, 'tueur')
end)

verifier('kill : dégât absent refusé', function()
    local src = Validation.tueurCreditable(nil, 9000, 10000, true, 8)
    egal(nil, src, 'tueur')
end)

verifier("kill : tueur d'un autre mode refusé", function()
    local src = Validation.tueurCreditable({ src = 7, at = 5000, weapon = 42 }, 9000, 10000, false, 8)
    egal(nil, src, 'tueur')
end)

verifier('kill : auto-kill refusé', function()
    local src = Validation.tueurCreditable({ src = 7, at = 5000, weapon = 42 }, 9000, 10000, true, 7)
    egal(nil, src, 'tueur')
end)

verifier('kill : fenêtre invalide refusée', function()
    local src = Validation.tueurCreditable({ src = 7, at = 5000, weapon = 42 }, 9000, 0 / 0, true, 8)
    egal(nil, src, 'tueur')
end)

-- ---------------------------------------------------------------- mort
verifier('mort : santé nulle confirmée', function()
    local ok, raison = Validation.mortConfirmee(1, {
        ped = function() return 5 end,
        health = function() return 0 end,
    })
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('mort', raison, 'raison')
end)

verifier('mort : joueur vivant refusé', function()
    local ok, raison = Validation.mortConfirmee(1, {
        ped = function() return 5 end,
        health = function() return 150 end,
    })
    egal(false, ok, 'ok')
    egal('vivant', raison, 'raison')
end)

verifier('mort : ped absent refusé', function()
    local ok, raison = Validation.mortConfirmee(1, {
        ped = function() return 0 end,
        health = function() return 0 end,
    })
    egal(false, ok, 'ok')
    egal('ped', raison, 'raison')
end)

verifier('mort : native dead prioritaire sur une santé encore positive', function()
    local ok, raison = Validation.mortConfirmee(1, {
        ped = function() return 5 end,
        health = function() return 150 end,
        dead = function() return true end,
    })
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('mort', raison, 'raison')
end)

verifier('mort : native dead muette, santé nulle acceptée', function()
    local ok, raison = Validation.mortConfirmee(1, {
        ped = function() return 5 end,
        health = function() return 0 end,
        dead = function() return false end,
    })
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('mort', raison, 'raison')
end)

verifier('mort : native dead en erreur, santé positive refusée', function()
    local ok, raison = Validation.mortConfirmee(1, {
        ped = function() return 5 end,
        health = function() return 150 end,
        dead = function() error('native absente') end,
    })
    egal(false, ok, 'ok')
    egal('vivant', raison, 'raison')
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
