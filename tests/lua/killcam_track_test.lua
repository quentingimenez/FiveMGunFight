-- Test du module de suivi gf_killcam/track.lua (contrat GFKillcamTrack).
-- Lancement : lua5.4 tests/lua/killcam_track_test.lua  (ou GF_ROOT=<racine> du dépôt).
-- Le module est chargé avec loadfile(path, 't', env) dans un environnement simulé :
-- ni FiveM, ni dépendance externe. Aucune règle métier n'est recopiée ici.

local root = os.getenv('GF_ROOT') or '.'
local base = root .. '/server-data/resources/[gunfight]/gf_killcam/'

local ok = 0

local function check(condition, message)
    if not condition then
        io.stderr:write(('ECHEC : %s\n'):format(tostring(message)))
        os.exit(1)
    end
    ok = ok + 1
end

-- ---------------------------------------------------------------------------
-- Chargement du vrai module dans un environnement minimal.
-- ---------------------------------------------------------------------------
local env = setmetatable({}, { __index = _G })
assert(loadfile(base .. 'track.lua', 't', env))()
local Track = assert(env.GFKillcamTrack, 'GFKillcamTrack absent de track.lua')

local function sample(t, x, h)
    return {
        t = t or 0, x = x or 0, y = 0, z = 0,
        h = h or 0, cx = 0, cy = 0, cz = 0, rx = 0, ry = 0, rz = 0,
        w = 0, a = false, s = false, v = 0,
    }
end

local function nan()
    return 0 / 0
end

local function inf()
    return math.huge
end

-- ---------------------------------------------------------------------------
-- clean : validation et assainissement d'un lot.
-- ---------------------------------------------------------------------------
do
    local lot = { sample(0, 1, -10), sample(100, 2, 370) }
    local cleaned = assert(Track.clean(lot), 'clean : lot valide refusé')
    check(#cleaned == 2, 'clean : bonne longueur du lot accepté')
    check(cleaned[1].t == 0 and cleaned[2].t == 100, 'clean : champs t conservés')
    check(cleaned[1].x == 1 and cleaned[2].x == 2, 'clean : champs x conservés')
    check(cleaned[1].h == 350, 'clean : h=-10 normalisé en 350')
    check(cleaned[2].h == 10, 'clean : h=370 normalisé en 10')
end

check(Track.clean(nil) == nil, 'clean : nil refusé')
check(Track.clean(42) == nil, 'clean : non-table refusé')
check(Track.clean({}) == nil, 'clean : lot vide refusé')

do
    local lot = {}
    for i = 1, 15 do lot[i] = sample(i * 100) end
    check(Track.clean(lot) ~= nil, 'clean : 15 échantillons acceptés')
    lot[16] = sample(1600)
    check(Track.clean(lot) == nil, 'clean : 16 échantillons refusés')
end

-- Un seul champ numérique invalide invalide tout le lot.
for _, field in ipairs({ 't', 'x', 'y', 'z', 'h', 'cx', 'cy', 'cz', 'rx', 'ry', 'rz' }) do
    local lot = { sample(0), sample(100) }
    lot[2][field] = nan()
    check(Track.clean(lot) == nil, 'clean : NaN sur ' .. field .. ' refusé')
    lot[2][field] = inf()
    check(Track.clean(lot) == nil, 'clean : infini sur ' .. field .. ' refusé')
    lot[2][field] = -inf()
    check(Track.clean(lot) == nil, 'clean : infini négatif sur ' .. field .. ' refusé')
end

-- Bornes spatiales des positions de ped et de caméra.
for _, field in ipairs({ 'x', 'y', 'z', 'cx', 'cy', 'cz' }) do
    local lot = { sample(0) }
    lot[1][field] = 20001
    check(Track.clean(lot) == nil, 'clean : ' .. field .. ' > 20000 refusé')
    lot[1][field] = -20001
    check(Track.clean(lot) == nil, 'clean : ' .. field .. ' < -20000 refusé')
    lot[1][field] = 20000
    check(Track.clean(lot) ~= nil, 'clean : ' .. field .. ' = 20000 accepté')
    lot[1][field] = -20000
    check(Track.clean(lot) ~= nil, 'clean : ' .. field .. ' = -20000 accepté')
end

-- Booléens stricts.
for _, field in ipairs({ 'a', 's' }) do
    local lot = { sample(0) }
    lot[1][field] = 1
    check(Track.clean(lot) == nil, 'clean : ' .. field .. ' nombre refusé')
    lot[1][field] = 'true'
    check(Track.clean(lot) == nil, 'clean : ' .. field .. ' chaîne refusée')
    lot[1][field] = true
    check(Track.clean(lot) ~= nil, 'clean : ' .. field .. ' booléen accepté')
end

-- Entiers stricts pour l'arme et le véhicule.
for _, field in ipairs({ 'w', 'v' }) do
    for _, bad in ipairs({ 3.5, '3', true }) do
        local lot = { sample(0) }
        lot[1][field] = bad
        check(Track.clean(lot) == nil,
            'clean : ' .. field .. '=' .. tostring(bad) .. ' refusé')
    end
    local lot = { sample(0) }
    lot[1][field] = 3.0
    check(Track.clean(lot) ~= nil, 'clean : ' .. field .. '=3.0 accepté comme entier')
    lot[1][field] = 0.0
    check(Track.clean(lot) ~= nil, 'clean : ' .. field .. '=0.0 accepté comme entier')
end

-- Un échantillon invalide invalide tout le lot (contrôle fait sur le 2e).
do
    local lot = { sample(0), sample(100) }
    lot[2].s = 1
    check(Track.clean(lot) == nil, 'clean : lot entier refusé si un échantillon est invalide')
end

-- ---------------------------------------------------------------------------
-- slice : fenêtre glissante, bornes incluses, sans mutation du tampon.
-- ---------------------------------------------------------------------------
do
    local buffer = {}
    for i = 0, 4 do buffer[i + 1] = sample(i * 1000, i) end
    local before = {}
    for i = 1, #buffer do before[i] = buffer[i] end

    local window = assert(Track.slice(buffer, 4000, 2), 'slice : fenêtre 2s')

    check(#window == 3, 'slice : 3 échantillons entre 2000 et 4000')
    check(window[1].t == 0 and window[2].t == 1000 and window[3].t == 2000,
        'slice : t ramenés au début de la fenêtre')
    check(window[1].x == 2 and window[3].x == 4, 'slice : ordre croissant conservé')
    check(#buffer == 5 and buffer[5] == before[5] and buffer[5].t == 4000,
        'slice : tampon d’origine non modifié')

    local all = assert(Track.slice(buffer, 4000, 4), 'slice : fenêtre 4s')
    check(#all == 5 and all[1].t == 0 and all[5].t == 4000,
        'slice : fenêtre plus large garde tout avec t relatifs 0..4000')

    local empty = Track.slice({}, 4000, 2)
    check(type(empty) == 'table' and #empty == 0, 'slice : tampon vide donne une liste vide')
end

-- ---------------------------------------------------------------------------
-- sample : interpolation linéaire, angles par le plus court chemin, bordures.
-- ---------------------------------------------------------------------------
do
    local a, b = sample(0, 0, 350), sample(1000, 10, 10)
    a.w, b.w, a.a, b.a, a.s, b.s, a.v, b.v = 7, 9, false, true, true, false, 1, 2

    local middle = assert(Track.sample({ a, b }, 500), 'sample : interpolation')
    check(math.abs(middle.x - 5) < 1e-6, 'sample : x interpolé à 5')
    check(math.abs(middle.h) < 1e-6 or math.abs(middle.h - 360) < 1e-6,
        'sample : h à mi-course de 350 vers 10 = 0 modulo 360')

    check(middle.w == 7, 'sample : w de l’échantillon précédent')
    check(middle.a == false, 'sample : a de l’échantillon précédent')
    check(middle.s == true, 'sample : s de l’échantillon précédent')
    check(middle.v == 1, 'sample : v de l’échantillon précédent')

    check(Track.sample({}, 500) == nil, 'sample : liste vide -> nil')

    local single = assert(Track.sample({ a }, 999999), 'sample : un seul échantillon')
    check(single.x == 0 and single.h == 350 and single.t == a.t,
        'sample : un seul échantillon renvoie une copie')

    local before = assert(Track.sample({ a, b }, -100), 'sample : avant le premier')
    check(before.x == 0 and before.h == 350, 'sample : borne basse tenue (premier échantillon)')

    local after = assert(Track.sample({ a, b }, 5000), 'sample : après le dernier')
    check(after.x == 10 and (after.h == 10 or after.h == 370),
        'sample : borne haute tenue (dernier échantillon)')
end

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
