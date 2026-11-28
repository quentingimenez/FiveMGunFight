-- =============================================================================
--  gf_core - tests du marqueur de plantage (module client pur).
--
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/crash_marker_test.lua
--  Le KVP est simulé par une table Lua : aucune native FiveM n'est appelée.
-- =============================================================================

package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

local sb = F.sandbox({ resource = 'gf_core' })
sb:load('server-data/resources/[gunfight]/gf_core/crash_marker.lua')
local CrashMarker = assert(sb.env.CrashMarker, 'global CrashMarker')

-- État neuf pour chaque scénario : `store` simule les KVP, `trace` compte les
-- appels et garde leur ordre. Le module ne reçoit que les trois fonctions
-- nommées get/set/del, jamais la table de stockage elle-même.
local function fresh(cle, prefixe)
    local store = {}
    local trace = { get = 0, set = 0, del = 0, ops = {} }
    local kvp = {
        get = function(key)
            trace.get = trace.get + 1
            return store[key]
        end,
        set = function(key, value)
            trace.set = trace.set + 1
            trace.ops[#trace.ops + 1] = 'set:' .. key
            store[key] = value
        end,
        del = function(key)
            trace.del = trace.del + 1
            trace.ops[#trace.ops + 1] = 'del:' .. key
            store[key] = nil
        end,
    }
    return store, trace, CrashMarker.new(cle, prefixe, kvp)
end

-- a) Démarrage sans marqueur : recover ne fait rien et renvoie un seul nil.
do
    local store, trace, marker = fresh('cle', 'prefix:')
    local ref, version = marker:recover()
    T.equal(ref, nil, 'sans marqueur : aucune référence')
    T.equal(version, nil, 'sans marqueur : aucune version')
    T.equal(select('#', marker:recover()), 1, 'sans marqueur : un seul retour')
    T.check(next(store) == nil, 'sans marqueur : KVP laissé vide')
    T.equal(trace.set, 0, 'sans marqueur : aucun set')
    T.equal(trace.del, 0, 'sans marqueur : aucun del')
end

-- a bis) Un marqueur vide vaut l'absence de marqueur.
do
    local store, trace, marker = fresh('cle', 'prefix:')
    store.cle = ''
    local ref, version = marker:recover()
    T.equal(ref, nil, 'marqueur vide : aucune référence')
    T.equal(version, nil, 'marqueur vide : aucune version')
    T.equal(select('#', marker:recover()), 1, 'marqueur vide : un seul retour')
    T.equal(store.cle, '', 'marqueur vide : laissé tel quel')
    T.equal(trace.set, 0, 'marqueur vide : aucun set')
    T.equal(trace.del, 0, 'marqueur vide : aucun del')
end

-- b) begin puis recover simule un plantage : mise de côté écrite avant
--    l'effacement du marqueur, et deux valeurs renvoyées.
do
    local store, trace, marker = fresh('cle', 'prefix:')
    marker:begin('veh', '7')
    T.equal(store.cle, 'veh@7', 'begin : marqueur écrit')
    local ref, version = marker:recover()
    T.equal(store.cle, nil, 'recover : marqueur effacé')
    T.equal(store['prefix:veh'], '7', 'recover : mise de côté écrite')
    T.equal(ref, 'veh', 'recover : référence renvoyée')
    T.equal(version, '7', 'recover : version renvoyée')
    T.equal(table.concat(trace.ops, ','), 'set:cle,set:prefix:veh,del:cle', 'recover : écriture avant effacement')
end

-- c) begin puis finish : marqueur effacé, aucune mise de côté.
do
    local store, trace, marker = fresh('cle', 'prefix:')
    marker:begin('veh', '7')
    marker:finish()
    T.equal(store.cle, nil, 'finish : marqueur effacé')
    T.check(next(store) == nil, 'finish : aucune mise de côté')
    T.equal(trace.set, 1, 'finish : aucune écriture de mise de côté')
    T.equal(trace.del, 1, 'finish : un seul effacement')
end

-- d) isBad dépend de la version ; une version absente vaut '0'.
do
    local _, _, marker = fresh('cle', 'prefix:')
    marker:begin('veh', '7')
    local ref = marker:recover()
    T.check(marker:isBad(ref, '7'), 'isBad : vrai pour la version du plantage')
    T.check(not marker:isBad(ref, '8'), 'isBad : faux pour une autre version')
end

do
    local store, _, marker = fresh('cle', 'prefix:')
    marker:begin('ref', nil)
    T.equal(store.cle, 'ref@0', 'begin sans version : marqueur ref@0')
    local ref, version = marker:recover()
    T.equal(ref, 'ref', 'begin sans version : référence renvoyée')
    T.equal(version, '0', 'begin sans version : version 0 renvoyée')
    T.check(marker:isBad(ref), 'isBad sans version : vrai')
    T.check(marker:isBad(ref, '0'), 'isBad avec version 0 : vrai')
end

-- d bis) begin convertit une version numérique en chaîne.
do
    local store, _, marker = fresh('cle', 'prefix:')
    marker:begin('arms', 5)
    T.equal(store.cle, 'arms@5', 'begin : version numérique convertie')
end

-- e) clear efface la mise de côté sans toucher au marqueur.
do
    local store, trace, marker = fresh('cle', 'prefix:')
    store['prefix:veh'] = '7'
    marker:clear('veh')
    T.equal(store['prefix:veh'], nil, 'clear : mise de côté effacée')
    T.equal(store.cle, nil, 'clear : aucun marqueur créé')
    T.equal(table.concat(trace.ops, ','), 'del:prefix:veh', 'clear : un seul effacement')
end

-- f) Marqueur sans '@' : référence entière et version '0'.
do
    local store, _, marker = fresh('cle', 'prefix:')
    store.cle = 'abc'
    local ref, version = marker:recover()
    T.equal(ref, 'abc', 'sans @ : référence entière')
    T.equal(version, '0', 'sans @ : version 0')
    T.equal(store['prefix:abc'], '0', 'sans @ : mise de côté 0')
    T.equal(store.cle, nil, 'sans @ : marqueur effacé')
end

-- f bis) Cas volontairement conservé : une valeur finissant par '@' garde
--        une version vide (le motif Lua `^([^@]+)@(.*)$` le produit ainsi).
do
    local store, _, marker = fresh('cle', 'prefix:')
    store.cle = 'x@'
    local ref, version = marker:recover()
    T.equal(ref, 'x', 'valeur finissant par @ : référence')
    T.equal(version, '', 'valeur finissant par @ : version vide conservée')
    T.equal(store['prefix:x'], '', 'valeur finissant par @ : mise de côté vide')
end

-- g) Les deux jeux de clés réelles, à l'identique.
do
    local store, _, marker = fresh('gf_core:vehicleLoading', 'gf_core:badv:')
    marker:begin('adder', '3')
    T.equal(store['gf_core:vehicleLoading'], 'adder@3', 'gf_core : marqueur réel')
    local ref, version = marker:recover()
    T.equal(ref, 'adder', 'gf_core : référence')
    T.equal(version, '3', 'gf_core : version')
    T.equal(store['gf_core:badv:adder'], '3', 'gf_core : mise de côté réelle')
    T.equal(store['gf_core:vehicleLoading'], nil, 'gf_core : marqueur effacé')
    T.check(marker:isBad('adder', '3'), 'gf_core : isBad vrai pour la version')
    T.check(not marker:isBad('adder', '4'), 'gf_core : isBad faux pour une autre version')
end

do
    local store, _, marker = fresh('gf_thumbs:inflight', 'gf_thumbs:badv:')
    marker:begin('vehicles/adder', '42')
    T.equal(store['gf_thumbs:inflight'], 'vehicles/adder@42', 'gf_thumbs : marqueur réel')
    local ref, version = marker:recover()
    T.equal(ref, 'vehicles/adder', 'gf_thumbs : référence')
    T.equal(version, '42', 'gf_thumbs : version')
    T.equal(store['gf_thumbs:badv:vehicles/adder'], '42', 'gf_thumbs : mise de côté réelle')
    T.equal(store['gf_thumbs:inflight'], nil, 'gf_thumbs : marqueur effacé')
end

T.finish('CrashMarker')
