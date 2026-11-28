-- =============================================================================
--  Harnais d'assertions partagé par les tests Lua (chantier C18).
--
--  package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
--  local T = require('assert')
--  T.check(condition, 'message')
--  T.equal(obtenu, attendu, 'message')
--  T.deepEqual(t1, t2, 'message')
--  T.raises(function() error('boom') end, 'boo', 'message')
--  T.finish('mon test')
--
--  Un échec affiche une ligne « ÉCHEC : ... » et n'interrompt pas la suite.
--  T.finish affiche le bilan en dernière ligne et sort avec le code 1 s'il y a
--  eu au moins un échec. Aucune assertion n'utilise le assert global.
-- =============================================================================

local T = {}

local passed, failed = 0, 0

local function fail(message)
    failed = failed + 1
    io.stdout:write('ÉCHEC : ' .. tostring(message) .. '\n')
end

function T.check(cond, message)
    if cond then
        passed = passed + 1
    else
        fail(message)
    end
end

function T.equal(obtenu, attendu, message)
    if obtenu == attendu then
        passed = passed + 1
    else
        fail(('%s : obtenu %s, attendu %s'):format(
            tostring(message), tostring(obtenu), tostring(attendu)))
    end
end

local function deepCompare(a, b, seenA, seenB, path)
    -- Même référence : vrai, y compris pour une table cyclique déjà revisitée.
    if a == b then return true, nil end

    local ta, tb = type(a), type(b)
    if ta ~= 'table' or tb ~= 'table' then
        if ta ~= tb then
            return false, ('%s : types %s/%s (%s/%s)'):format(path, ta, tb, tostring(a), tostring(b))
        end
        return false, ('%s : %s ~= %s'):format(path, tostring(a), tostring(b))
    end

    local seenAForA = seenA[a]
    local seenBForB = seenB[b]
    if seenAForA ~= nil or seenBForB ~= nil then
        -- Deux cycles appariés sont acceptés ; un cycle d'un seul côté ne l'est pas.
        if seenAForA ~= nil and seenBForB ~= nil and seenAForA == b and seenBForB == a then
            return true, nil
        end
        return false, ('%s : structure cyclique non correspondante'):format(path)
    end

    seenA[a], seenB[b] = b, a

    for key, valueA in pairs(a) do
        local valueB = b[key]
        local childPath = ('%s[%s]'):format(path, tostring(key))
        local ok, why = deepCompare(valueA, valueB, seenA, seenB, childPath)
        if not ok then return false, why end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false, ('%s[%s] : clé absente du premier tableau'):format(path, tostring(key))
        end
    end

    seenA[a], seenB[b] = nil, nil
    return true, nil
end

function T.deepEqual(a, b, message)
    local ok, why = deepCompare(a, b, {}, {}, tostring(message) or 'deepEqual')
    if ok then
        passed = passed + 1
    else
        fail(('%s : %s'):format(tostring(message), why or 'tables différentes'))
    end
end

function T.raises(fn, motif, message)
    local success, err = pcall(fn)
    local ok, why
    if success then
        ok, why = false, 'aucune erreur levée'
    elseif motif ~= nil and not tostring(err):find(motif) then
        -- string.find avec motif Lua (patterns) : '^prefix', '%d+', etc.
        ok, why = false, ('erreur %s ne correspond pas à %s'):format(tostring(err), tostring(motif))
    else
        ok = true
    end

    if ok then
        passed = passed + 1
    else
        fail(('%s : %s'):format(tostring(message), why))
    end
end

function T.finish(nom)
    io.stdout:write(('%s : %d test(s) réussi(s), %d échec(s)\n')
        :format(tostring(nom), passed, failed))
    io.stdout:flush()
    if failed > 0 then os.exit(1) end
end

return T
