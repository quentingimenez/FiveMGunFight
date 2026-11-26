-- =============================================================================
--  Tests unitaires du module serveur pur gf_core/shot_validation.lua.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/shot_validation_test.lua
--  Aucune native FiveM n'est appelée : les instants sont fournis par les tests.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/shot_validation_test%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()
local MODULES = RACINE .. '/server-data/resources/[gunfight]/gf_core/'

dofile(MODULES .. 'shot_validation.lua')

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

local PISTOL = 453432689
local UNARMED = 2725352035
local CARBINERIFLE = 2210333304

--- Règles minimales : toutes les armes sont autorisées, sans plafond ni cadence.
local function reglesSimples(surcharges)
    local regles = {
        autorisees = nil,
        toujoursAutorisees = {},
        plafonds = {},
        composantsTete = { [20] = true },
        cadences = {},
        toleranceMs = 0,
    }
    for cle, valeur in pairs(surcharges or {}) do regles[cle] = valeur end
    return regles
end

local function touche(arme, degat, composant, instant)
    return { arme = arme, degat = degat, composant = composant, instant = instant }
end

-- ---------------------------------------------------------------- joaat
verifier('joaat : valeurs de contrôle GTA', function()
    egal(PISTOL, ShotValidation.joaat('WEAPON_PISTOL'), 'WEAPON_PISTOL')
    egal(CARBINERIFLE, ShotValidation.joaat('WEAPON_CARBINERIFLE'), 'WEAPON_CARBINERIFLE')
    egal(UNARMED, ShotValidation.joaat('WEAPON_UNARMED'), 'WEAPON_UNARMED')
end)

verifier('joaat : insensible à la casse', function()
    egal(PISTOL, ShotValidation.joaat('weapon_pistol'), 'weapon_pistol')
    egal(ShotValidation.joaat('WEAPON_PISTOL'), ShotValidation.joaat('WeApOn_PiStOl'), 'casse mélangée')
end)

verifier('joaat : résultat borné sur 32 bits', function()
    local hash = ShotValidation.joaat('weapon_unarmed')
    vrai(hash >= 0 and hash <= 0xFFFFFFFF, 'hash hors bornes')
    egal(UNARMED, hash, 'borne 32 bits')
end)

-- ---------------------------------------------------------------- normaliserHash
verifier('normaliserHash : hash négatif converti en non signé', function()
    egal(UNARMED, ShotValidation.normaliserHash(-1569615261), 'WEAPON_UNARMED')
end)

verifier('normaliserHash : hash positif inchangé', function()
    egal(PISTOL, ShotValidation.normaliserHash(PISTOL), 'WEAPON_PISTOL')
    egal(0, ShotValidation.normaliserHash(0), 'zéro')
end)

verifier('normaliserHash : valeurs invalides refusées', function()
    egal(nil, ShotValidation.normaliserHash(12.5), 'décimal')
    local nan = 0 / 0
    egal(nil, ShotValidation.normaliserHash(nan), 'NaN')
    egal(nil, ShotValidation.normaliserHash('abc'), 'chaîne')
    egal(nil, ShotValidation.normaliserHash(nil), 'nil')
    egal(nil, ShotValidation.normaliserHash(math.huge), 'infini positif')
    egal(nil, ShotValidation.normaliserHash(-math.huge), 'infini négatif')
    egal(nil, ShotValidation.normaliserHash(true), 'booléen')
end)

-- ---------------------------------------------------------------- ensembleArmes
verifier('ensembleArmes : noms convertis en hashes', function()
    local ensemble = ShotValidation.ensembleArmes({ 'WEAPON_PISTOL', 'weapon_carbinerifle', 42, nil, {} })
    vrai(ensemble[PISTOL], 'pistol présent')
    vrai(ensemble[CARBINERIFLE], 'carbinerifle présent')
    egal(nil, ensemble[42], 'nombre ignoré')
end)

verifier('ensembleArmes : entrée non-table donne un ensemble vide', function()
    local vide = ShotValidation.ensembleArmes(nil)
    egal(nil, next(vide), 'nil')
    egal(nil, next(ShotValidation.ensembleArmes('WEAPON_PISTOL')), 'chaîne')
end)

-- ---------------------------------------------------------------- loadout
verifier('tir : arme du loadout acceptée', function()
    local etat = {}
    local regles = reglesSimples({ autorisees = { [PISTOL] = true } })
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles)
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('ok', raison, 'raison')
end)

verifier('tir : arme hors loadout refusée', function()
    local etat = {}
    local regles = reglesSimples({ autorisees = { [PISTOL] = true } })
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(CARBINERIFLE, 10, 0, 1000), regles)
    egal(false, ok, 'ok')
    egal('arme-hors-loadout', raison, 'raison')
    egal(nil, etat[1], 'état inchangé')
end)

verifier('tir : autorisees nil accepte toutes les armes', function()
    local etat = {}
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(CARBINERIFLE, 10, 0, 1000), reglesSimples())
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('ok', raison, 'raison')
end)

verifier('tir : poings acceptés même hors loadout', function()
    local etat = {}
    local regles = reglesSimples({
        autorisees = { [PISTOL] = true },
        toujoursAutorisees = { [UNARMED] = true },
    })
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(UNARMED, 10, 0, 1000), regles)
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('ok', raison, 'raison')
    egal(nil, etat[1], 'état non mis à jour pour une arme toujours autorisée')
end)

-- ---------------------------------------------------------------- validité
verifier('tir : touche non-table refusée', function()
    local ok, raison = ShotValidation.verifierTouche({}, 1, nil, reglesSimples())
    egal(false, ok, 'ok')
    egal('arme-invalide', raison, 'raison')
end)

verifier('tir : arme non normalisable refusée', function()
    local etat = {}
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche('pistolet', 10, 0, 1000), reglesSimples())
    egal(false, ok, 'ok')
    egal('arme-invalide', raison, 'raison')
    egal(nil, etat[1], 'état inchangé')
end)

verifier('tir : dégâts invalides refusés', function()
    local etat = {}
    local invalides = { -1, 0 / 0, '10', math.huge, -math.huge }
    for _, degat in ipairs(invalides) do
        local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, degat, 0, 1000), reglesSimples())
        egal(false, ok, 'ok pour ' .. tostring(degat))
        egal('degat-invalide', raison, 'raison pour ' .. tostring(degat))
    end
    egal(nil, etat[1], 'état inchangé')
end)

verifier('tir : dégât nul accepté', function()
    local ok, raison = ShotValidation.verifierTouche({}, 1, touche(PISTOL, 0, 0, 1000), reglesSimples())
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('ok', raison, 'raison')
end)

-- ---------------------------------------------------------------- plafonds
verifier('plafond : corps au plafond accepté, au-dessus refusé', function()
    local regles = reglesSimples({ plafonds = { [PISTOL] = { corps = 30, tete = 90 } } })
    local ok, raison = ShotValidation.verifierTouche({}, 1, touche(PISTOL, 30, 7, 1000), regles)
    vrai(ok, 'au plafond refusé : ' .. tostring(raison))
    ok, raison = ShotValidation.verifierTouche({}, 2, touche(PISTOL, 30.1, 7, 1000), regles)
    egal(false, ok, 'au-dessus')
    egal('degat-plafond', raison, 'raison')
end)

verifier('plafond : tête utilise le plafond tête, pas le plafond corps', function()
    local regles = reglesSimples({ plafonds = { [PISTOL] = { corps = 30, tete = 90 } } })
    local ok, raison = ShotValidation.verifierTouche({}, 1, touche(PISTOL, 60, 20, 1000), regles)
    vrai(ok, '60 en tête devrait être accepté : ' .. tostring(raison))
    ok, raison = ShotValidation.verifierTouche({}, 2, touche(PISTOL, 90.1, 20, 1000), regles)
    egal(false, ok, 'au-dessus du plafond tête')
    egal('degat-plafond', raison, 'raison')
end)

verifier('plafond : tête sans plafond tete retombe sur corps', function()
    local regles = reglesSimples({ plafonds = { [PISTOL] = { corps = 30 } } })
    local ok, raison = ShotValidation.verifierTouche({}, 1, touche(PISTOL, 31, 20, 1000), regles)
    egal(false, ok, 'ok')
    egal('degat-plafond', raison, 'raison')
end)

verifier('plafond : aucun plafond configuré, tout dégât fini accepté', function()
    local ok, raison = ShotValidation.verifierTouche({}, 1, touche(PISTOL, 10000, 20, 1000), reglesSimples())
    vrai(ok, 'refusé : ' .. tostring(raison))
    egal('ok', raison, 'raison')
end)

-- ---------------------------------------------------------------- cadence
verifier('cadence : intervalle nul accepté (plombs d\'un même tir)', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 0 })
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles)
    vrai(ok, '1re touche : ' .. tostring(raison))
    ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles)
    vrai(ok, '2e touche à intervalle nul : ' .. tostring(raison))
    egal('ok', raison, 'raison')
end)

verifier('cadence : intervalle trop court refusé', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 20 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), '1re touche')
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1100), regles)
    egal(false, ok, 'ok')
    egal('cadence', raison, 'raison')
    egal(1000, etat[1].instant, 'état non mis à jour après refus')
end)

verifier('cadence : intervalle égal à cadence moins tolérance accepté', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 20 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), '1re touche')
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1180), regles)
    vrai(ok, 'limite acceptée : ' .. tostring(raison))
    egal('ok', raison, 'raison')
    egal(1180, etat[1].instant, 'état mis à jour')
end)

verifier('cadence : intervalle négatif accepté sans mise à jour', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 0 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), '1re touche')
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 900), regles)
    vrai(ok, 'désordre réseau accepté : ' .. tostring(raison))
    egal('ok', raison, 'raison')
    egal(1000, etat[1].instant, 'état inchangé')
end)

verifier('cadence : instants non finis ne bloquent pas', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 0 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), '1re touche')
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 0 / 0), regles)
    vrai(ok, 'NaN accepté : ' .. tostring(raison))
    egal('ok', raison, 'raison')
end)

verifier('cadence : changement d\'arme sans contrôle', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200, [CARBINERIFLE] = 500 }, toleranceMs = 0 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), '1re touche')
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(CARBINERIFLE, 10, 0, 1010), regles)
    vrai(ok, 'arme différente acceptée : ' .. tostring(raison))
    egal('ok', raison, 'raison')
    egal(CARBINERIFLE, etat[1].arme, 'arme mise à jour')
end)

verifier('cadence : tireurs indépendants', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 0 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), 'tireur 1')
    local ok = ShotValidation.verifierTouche(etat, 2, touche(PISTOL, 10, 0, 1010), regles)
    vrai(ok, 'tireur 2 indépendant')
end)

verifier('cadence : instants non numériques acceptés sans modifier l\'état', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 0 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), '1re touche')

    for _, instantInvalide in ipairs({ {}, 'abc' }) do
        local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, instantInvalide), regles)
        vrai(ok, 'instant invalide accepté : ' .. tostring(raison))
        egal('ok', raison, 'raison')
        egal(1000, etat[1].instant, 'état inchangé')
        egal(PISTOL, etat[1].arme, 'arme inchangée')
    end

    -- La cadence fonctionne toujours après ces touches invalides.
    local ok, raison = ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1200), regles)
    vrai(ok, 'touche normale acceptée : ' .. tostring(raison))
    egal('ok', raison, 'raison')
    egal(1200, etat[1].instant, 'état mis à jour')
end)

-- ---------------------------------------------------------------- oubli
verifier('oublier : remet l\'état à zéro', function()
    local etat = {}
    local regles = reglesSimples({ cadences = { [PISTOL] = 200 }, toleranceMs = 0 })
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1000), regles), '1re touche')
    egal(false, ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1100), regles), 'bloqué avant oubli')
    ShotValidation.oublier(etat, 1)
    egal(nil, etat[1], 'entrée supprimée')
    vrai(ShotValidation.verifierTouche(etat, 1, touche(PISTOL, 10, 0, 1100), regles), 'accepté après oubli')
end)

verifier('oublier : état non-table sans effet', function()
    ShotValidation.oublier(nil, 1)
    ShotValidation.oublier('x', 1)
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
