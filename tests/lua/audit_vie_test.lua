-- =============================================================================
--  Tests unitaires du module serveur pur gf_audit/audit.lua.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/audit_vie_test.lua
--  Aucune native FiveM n'est appelée : le module est un simple module Lua.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/audit_vie_test%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()

dofile(RACINE .. '/server-data/resources/[gunfight]/gf_audit/audit.lua')

local REGLES = { fenetreMortMs = 3000, graceMs = 1000, tolerance = 2 }
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

-- ---------------------------------------------------------------- nouveau
verifier('nouveau : état vide', function()
    local etat = AuditVie.nouveau()
    egal('table', type(etat), 'type')
    local compte = 0
    for _ in pairs(etat) do compte = compte + 1 end
    egal(0, compte, 'nombre de joueurs')
end)

-- ---------------------------------------------------------------- apparition / grâce
verifier('apparition : première mesure après la grâce = référence', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    local anomalies = AuditVie.mesure(etat, 1, 100, 50, false, 1500, REGLES)
    egal(0, #anomalies, 'anomalies')
    egal(100, etat[1].vie, 'vie')
    egal(50, etat[1].armure, 'armure')
end)

verifier('grâce : hausse sans anomalie', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    egal(0, #AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES), 'référence')
    local anomalies = AuditVie.mesure(etat, 1, 150, 50, false, 800, REGLES)
    egal(0, #anomalies, 'anomalies')
end)

-- ---------------------------------------------------------------- soins sans objet
verifier('vie : hausse sans objet après la grâce', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    local anomalies = AuditVie.mesure(etat, 1, 150, 50, false, 1500, REGLES)
    egal(1, #anomalies, 'anomalies')
    egal('soin-sans-objet', anomalies[1].type, 'type')
    egal('vie', anomalies[1].stat, 'stat')
    egal(100, anomalies[1].avant, 'avant')
    egal(150, anomalies[1].apres, 'apres')
    egal(0, anomalies[1].permis, 'permis')
end)

verifier('armure : hausse sans objet après la grâce', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    local anomalies = AuditVie.mesure(etat, 1, 100, 80, false, 1500, REGLES)
    egal(1, #anomalies, 'anomalies')
    egal('soin-sans-objet', anomalies[1].type, 'type')
    egal('armure', anomalies[1].stat, 'stat')
    egal(50, anomalies[1].avant, 'avant')
    egal(80, anomalies[1].apres, 'apres')
    egal(0, anomalies[1].permis, 'permis')
end)

verifier('tolérance : hausse de 2 sans anomalie', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    local anomalies = AuditVie.mesure(etat, 1, 102, 50, false, 1500, REGLES)
    egal(0, #anomalies, 'anomalies')
end)

-- ---------------------------------------------------------------- objets
verifier('objet de vie : permis consommé puis épuisé', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    AuditVie.objetUtilise(etat, 1, 'health', 30, 3000, 600, REGLES)

    egal(0, #AuditVie.mesure(etat, 1, 130, 50, false, 2000, REGLES), 'hausse couverte')
    egal(0, etat[1].permis.vie, 'permis après consommation')

    local anomalies = AuditVie.mesure(etat, 1, 160, 50, false, 2500, REGLES)
    egal(1, #anomalies, 'anomalies')
    egal('soin-sans-objet', anomalies[1].type, 'type')
    egal('vie', anomalies[1].stat, 'stat')
    egal(130, anomalies[1].avant, 'avant')
    egal(160, anomalies[1].apres, 'apres')
    egal(0, anomalies[1].permis, 'permis')
end)

verifier('objet de vie : permis expiré', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    AuditVie.objetUtilise(etat, 1, 'health', 30, 3000, 600, REGLES)

    local anomalies = AuditVie.mesure(etat, 1, 130, 50, false, 5000, REGLES)
    egal(1, #anomalies, 'anomalies')
    egal('soin-sans-objet', anomalies[1].type, 'type')
    egal('vie', anomalies[1].stat, 'stat')
    egal(100, anomalies[1].avant, 'avant')
    egal(130, anomalies[1].apres, 'apres')
    egal(0, anomalies[1].permis, 'permis')
end)

verifier('dégât : baisse de vie sans anomalie', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    egal(0, #AuditVie.mesure(etat, 1, 70, 50, false, 1500, REGLES), 'anomalies')
end)

-- ---------------------------------------------------------------- mort
verifier('touche mortelle acceptée puis mort dans la fenêtre', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    AuditVie.touche(etat, 1, true, true, 1000)
    egal(0, #AuditVie.mesure(etat, 1, 0, 50, true, 1500, REGLES), 'anomalies')
    egal(nil, etat[1].vie, 'vie')
    egal(nil, etat[1].armure, 'armure')
    egal(nil, etat[1].mortelle, 'mortelle')
end)

verifier('touche mortelle acceptée sans mort au-delà de la fenêtre', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    AuditVie.touche(etat, 1, true, true, 1000)

    local anomalies = AuditVie.mesure(etat, 1, 100, 50, false, 4001, REGLES)
    egal(1, #anomalies, 'anomalies')
    egal('touche-mortelle-sans-mort', anomalies[1].type, 'type')
    vrai(anomalies[1].depuisMs > 3000, 'depuisMs')
    egal(3001, anomalies[1].depuisMs, 'depuisMs exact')
    egal(100, anomalies[1].vie, 'vie')
    egal(nil, etat[1].mortelle, 'mortelle nettoyée')
    egal(0, #AuditVie.mesure(etat, 1, 100, 50, false, 5000, REGLES), 'mesure suivante')
end)

verifier('touche mortelle refusée : aucune anomalie', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    AuditVie.touche(etat, 1, true, false, 1000)
    egal(0, #AuditVie.mesure(etat, 1, 100, 50, false, 5000, REGLES), 'anomalies')
end)

verifier('touche mortelle : la plus ancienne est conservée', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    AuditVie.touche(etat, 1, true, true, 1000)
    AuditVie.touche(etat, 1, true, true, 1500)

    local anomalies = AuditVie.mesure(etat, 1, 100, 50, false, 4001, REGLES)
    egal(1, #anomalies, 'anomalies')
    egal('touche-mortelle-sans-mort', anomalies[1].type, 'type')
    egal(3001, anomalies[1].depuisMs, 'depuisMs')
end)

-- ---------------------------------------------------------------- soin serveur
verifier('soinAccorde : nouvelle référence sans anomalie', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)
    AuditVie.soinAccorde(etat, 1, 1000, REGLES)

    egal(0, #AuditVie.mesure(etat, 1, 200, 50, false, 1500, REGLES), 'dans la grâce')
    egal(0, #AuditVie.mesure(etat, 1, 200, 50, false, 2500, REGLES), 'après la grâce')
end)

-- ---------------------------------------------------------------- validation
verifier('entrée non numérique : liste vide et état inchangé', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    AuditVie.mesure(etat, 1, 100, 50, false, 500, REGLES)

    local chaine = AuditVie.mesure(etat, 1, '100', 50, false, 2000, REGLES)
    egal(0, #chaine, 'anomalies chaîne')
    local nilVie = AuditVie.mesure(etat, 1, nil, 50, false, 2000, REGLES)
    egal(0, #nilVie, 'anomalies nil')
    local nan = AuditVie.mesure(etat, 1, 0 / 0, 50, false, 2000, REGLES)
    egal(0, #nan, 'anomalies NaN')
    local infini = AuditVie.mesure(etat, 1, math.huge, 50, false, 2000, REGLES)
    egal(0, #infini, 'anomalies infini')

    egal(100, etat[1].vie, 'vie inchangée')
    egal(50, etat[1].armure, 'armure inchangée')
    egal(500, etat[1].derniere, 'derniere inchangée')

    local sansEtat = AuditVie.mesure(nil, 1, 100, 50, false, 2000, REGLES)
    egal(0, #sansEtat, 'état nil')
end)

-- ---------------------------------------------------------------- oubli
verifier('oublier : joueur retiré de l’état', function()
    local etat = AuditVie.nouveau()
    AuditVie.apparition(etat, 1, 0, REGLES)
    vrai(etat[1] ~= nil, 'présent avant')
    AuditVie.oublier(etat, 1)
    egal(nil, etat[1], 'après oubli')
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
