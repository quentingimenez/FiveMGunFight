-- =============================================================================
--  Tests unitaires du module pur de planification des migrations.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/migration_plan_test.lua
--  Aucune native FiveM n'est appelée, aucune dépendance extérieure.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/migration_plan_test%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()
local MODULES = RACINE .. '/server-data/resources/[gunfight]/gf_db/'

dofile(MODULES .. 'plan.lua')

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

-- ---------------------------------------------------------------- somme FNV-1a
verifier('somme : chaîne vide', function()
    egal('811c9dc5', MigrationPlan.somme(''), 'somme vide')
end)

verifier('somme : lettre a', function()
    egal('e40c292c', MigrationPlan.somme('a'), 'somme de a')
end)

verifier('somme : CRLF normalisé en LF', function()
    egal(MigrationPlan.somme('a\n'), MigrationPlan.somme('a\r\n'), 'CRLF == LF')
end)

verifier('somme : format 8 hexadécimales minuscules', function()
    for _, texte in ipairs({ '', 'a', 'migration 001', '\0\255', 'é' }) do
        local somme = MigrationPlan.somme(texte)
        vrai(#somme == 8, 'longueur : ' .. somme)
        vrai(somme:match('^[0-9a-f]+$'), 'hexadécimal minuscule : ' .. somme)
    end
end)

-- ---------------------------------------------------------------- decouper
verifier('decouper : deux instructions avec commentaires et lignes vides', function()
    local sql = table.concat({
        '-- Migration 1',
        '',
        'CREATE TABLE a (',
        '  id INT PRIMARY KEY',
        ');',
        '',
        '-- Migration 2',
        'INSERT INTO a (id) VALUES (1);   ',
        '-- fin',
    }, '\n')
    local instructions = MigrationPlan.decouper(sql)
    egal(2, #instructions, 'nombre d\'instructions')
    egal('CREATE TABLE a (\n  id INT PRIMARY KEY\n)', instructions[1], 'instruction 1')
    egal('INSERT INTO a (id) VALUES (1)', instructions[2], 'instruction 2')
    for _, instruction in ipairs(instructions) do
        vrai(not instruction:find('--', 1, true), 'commentaire résiduel')
        vrai(not instruction:match(';%s*$'), 'point-virgule final résiduel')
    end
end)

verifier('decouper : entrée vide ou commentaires seulement', function()
    egal(0, #MigrationPlan.decouper(''), 'entrée vide')
    egal(0, #MigrationPlan.decouper('-- un commentaire\n\n   -- autre\n'), 'commentaires seuls')
end)

verifier('decouper : CRLF et instruction non terminée en fin de fichier', function()
    local sql = '-- entête\r\nSELECT 1;\r\nSELECT 2'
    local instructions = MigrationPlan.decouper(sql)
    egal(2, #instructions, 'nombre d\'instructions')
    egal('SELECT 1', instructions[1], 'instruction terminée')
    egal('SELECT 2', instructions[2], 'instruction non terminée')
end)

verifier('decouper : "--" au milieu d\'une ligne n\'est pas un commentaire', function()
    local instructions = MigrationPlan.decouper("SELECT '--pas un commentaire';")
    egal(1, #instructions, 'nombre d\'instructions')
    egal("SELECT '--pas un commentaire'", instructions[1], 'instruction conservée')
end)

-- ---------------------------------------------------------------- planifier
local connues = {
    { version = 1, nom = '001_init', somme = 'somme1' },
    { version = 2, nom = '002_data', somme = 'somme2' },
}

local function versions(liste)
    local resultat = {}
    for _, migration in ipairs(liste) do
        resultat[#resultat + 1] = migration.version
    end
    return table.concat(resultat, ',')
end

verifier('planifier : base vide -> toutes les migrations', function()
    local aAppliquer, erreur = MigrationPlan.planifier(connues, {})
    egal(nil, erreur, 'erreur')
    egal('1,2', versions(aAppliquer), 'versions à appliquer')
end)

verifier('planifier : une migration appliquée -> une seule en attente', function()
    local aAppliquer, erreur = MigrationPlan.planifier(connues, { [1] = 'somme1' })
    egal(nil, erreur, 'erreur')
    egal('2', versions(aAppliquer), 'versions à appliquer')
end)

verifier('planifier : base à jour -> liste vide', function()
    local aAppliquer, erreur = MigrationPlan.planifier(connues, { [1] = 'somme1', [2] = 'somme2' })
    egal(nil, erreur, 'erreur')
    egal(0, #aAppliquer, 'aucune migration')
end)

verifier('planifier : liste connue vide -> plan vide', function()
    local aAppliquer, erreur = MigrationPlan.planifier({}, {})
    egal(nil, erreur, 'erreur')
    egal(0, #aAppliquer, 'aucune migration')
end)

verifier('planifier : trou de numérotation -> numerotation', function()
    local aAppliquer, erreur = MigrationPlan.planifier({
        { version = 1, nom = 'a', somme = 's1' },
        { version = 3, nom = 'c', somme = 's3' },
    }, {})
    egal('numerotation', erreur, 'erreur')
    egal(0, #aAppliquer, 'plan vidé')
end)

verifier('planifier : version appliquée inconnue -> base-plus-recente', function()
    local aAppliquer, erreur = MigrationPlan.planifier(connues, { [3] = 'somme3' })
    egal('base-plus-recente', erreur, 'erreur')
    egal(0, #aAppliquer, 'plan vidé')
end)

verifier('planifier : somme modifiée -> migration-modifiee:1', function()
    local aAppliquer, erreur = MigrationPlan.planifier(connues, { [1] = 'autre' })
    egal('migration-modifiee:1', erreur, 'erreur')
    egal(0, #aAppliquer, 'plan vidé')
end)

verifier('planifier : priorité de la numérotation sur la base plus récente', function()
    local aAppliquer, erreur = MigrationPlan.planifier({
        { version = 2, nom = 'b', somme = 's2' },
    }, { [9] = 's9' })
    egal('numerotation', erreur, 'erreur prioritaire')
    egal(0, #aAppliquer, 'plan vidé')
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
