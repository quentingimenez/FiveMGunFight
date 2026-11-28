-- =============================================================================
--  gf_killcam - TRACK (module pur partagé, aucune native FiveM)
--  Table globale GFKillcamTrack : validation, découpe et interpolation des
--  échantillons de killcam. Aucun effet de bord : les tables reçues ne sont
--  jamais modifiées, seules des copies sont retournées.
-- =============================================================================

GFKillcamTrack = {}

-- Nombre maximum d'échantillons autorisés dans un lot réseau.
local LOT_MIN = 1
local LOT_MAX = 15

-- Bornes des positions (format FiveM : environ +/- 20000 mètres).
local POS_MIN, POS_MAX = -20000, 20000

-- Liste ordonnée des champs numériques finis d'un échantillon.
local CHAMPS_NOMBRES = { 't', 'x', 'y', 'z', 'h', 'cx', 'cy', 'cz', 'rx', 'ry', 'rz' }
-- Champs angles, normalisés dans [0, 360) après validation.
local CHAMPS_ANGLES = { 'h', 'rx', 'ry', 'rz' }
-- Champs de position, bornés à [-20000, 20000].
local CHAMPS_POSITION = { 'x', 'y', 'z', 'cx', 'cy', 'cz' }

--- Vrai si `valeur` est un nombre fini (rejette NaN et les infinis).
--- @param valeur any
--- @return boolean
local function estNombreFini(valeur)
    return type(valeur) == 'number'
        and valeur == valeur
        and valeur ~= math.huge
        and valeur ~= -math.huge
end

--- Vrai si `valeur` est un entier : accepte un flottant mathématiquement entier
--- (3.0), refuse les décimaux (3.5), les booléens et les chaînes.
--- @param valeur any
--- @return boolean
local function estEntier(valeur)
    if type(valeur) ~= 'number' or not estNombreFini(valeur) then return false end
    return math.tointeger(valeur) ~= nil
end

--- Ramène un angle dans [0, 360), y compris pour les valeurs négatives.
--- @param angle number
--- @return number
local function normaliserAngle(angle)
    local modulo = angle % 360
    if modulo < 0 then modulo = modulo + 360 end
    return modulo
end

--- Interpole un angle en prenant le plus court chemin en degrés.
--- Le delta est calculé dans (-180, 180], puis le résultat est normalisé.
--- @param a number angle de départ (déjà normalisé)
--- @param b number angle d'arrivée (déjà normalisé)
--- @param alpha number proportion [0, 1]
--- @return number angle interpolé dans [0, 360)
local function interpolerAngle(a, b, alpha)
    local delta = ((b - a + 180) % 360) - 180
    if delta < -180 then delta = delta + 360 end
    return normaliserAngle(a + delta * alpha)
end

--- Copie un échantillon déjà valide en une nouvelle table.
--- @param source table
--- @return table
local function copier(source)
    return {
        t = source.t,
        x = source.x, y = source.y, z = source.z, h = source.h,
        cx = source.cx, cy = source.cy, cz = source.cz,
        rx = source.rx, ry = source.ry, rz = source.rz,
        w = source.w, a = source.a, s = source.s, v = source.v,
    }
end

--- Valide un lot d'échantillons reçu du client et en retourne une copie saine.
--- Le lot entier est refusé dès qu'un échantillon est invalide, qu'il manque un
--- champ ou qu'un index est un trou. Les angles sont normalisés dans [0, 360).
--- @param lot any
--- @return table|nil liste copiée, ou nil si le lot est invalide
function GFKillcamTrack.clean(lot)
    if type(lot) ~= 'table' then return nil end

    local compte = #lot
    if compte < LOT_MIN or compte > LOT_MAX then return nil end

    local propre = {}
    for i = 1, compte do
        local brute = lot[i]
        -- Un index absent (trou dans la table) est une table non valide.
        if type(brute) ~= 'table' then return nil end

        for _, champ in ipairs(CHAMPS_NOMBRES) do
            if not estNombreFini(brute[champ]) then return nil end
        end
        for _, champ in ipairs(CHAMPS_POSITION) do
            local valeur = brute[champ]
            if valeur < POS_MIN or valeur > POS_MAX then return nil end
        end
        if type(brute.a) ~= 'boolean' or type(brute.s) ~= 'boolean' then return nil end
        if not estEntier(brute.w) or not estEntier(brute.v) then return nil end

        local copie = copier(brute)
        for _, champ in ipairs(CHAMPS_ANGLES) do
            copie[champ] = normaliserAngle(copie[champ])
        end
        propre[i] = copie
    end

    return propre
end

--- Découpe le tampon serveur sur la fenêtre [finMs - secondes*1000, finMs].
--- Seuls les échantillons dont `t` est dans la fenêtre sont retenus ; ils sont
--- triés par horloge serveur croissante et ramenés au début de la fenêtre
--- (leur `t` relatif est donc toujours >= 0).
--- Le tampon d'entrée n'est jamais modifié.
--- @param buffer table|nil liste d'échantillons horodatés par le serveur
--- @param finMs number horloge serveur de fin de fenêtre, en millisecondes
--- @param secondes number durée de la fenêtre, en secondes
--- @return table liste (jamais nil) d'échantillons copiés
function GFKillcamTrack.slice(buffer, finMs, secondes)
    local resultat = {}
    if type(buffer) ~= 'table' or #buffer == 0 then return resultat end
    if not estNombreFini(finMs) or not estNombreFini(secondes) then return resultat end

    local debutMs = finMs - secondes * 1000

    -- On copies d'abord les échantillons retenus, puis on les trie par `t`,
    -- afin de ne jamais toucher au tampon d'origine.
    local retenus = {}
    for i = 1, #buffer do
        local echantillon = buffer[i]
        if type(echantillon) == 'table' and estNombreFini(echantillon.t)
            and echantillon.t >= debutMs and echantillon.t <= finMs then
            retenus[#retenus + 1] = echantillon
        end
    end

    table.sort(retenus, function(a, b) return a.t < b.t end)

    for i = 1, #retenus do
        local copie = copier(retenus[i])
        copie.t = retenus[i].t - debutMs
        resultat[i] = copie
    end

    return resultat
end

--- Interpole un échantillon à l'instant `t` (horloge de la fenêtre).
--- Positions et cap en linéaire ; angles du plus court chemin en degrés ;
--- booléens, arme et véhicule pris sur l'échantillon précédent (celui dont
--- le `t` est <= t demandé). `t` est borné au premier et au dernier échantillon.
--- @param samples table|nil liste d'échantillons triée par `t`
--- @param t number instant demandé
--- @return table|nil échantillon interpolé, ou nil si la liste est vide
function GFKillcamTrack.sample(samples, t)
    if type(samples) ~= 'table' or #samples == 0 then return nil end
    if not estNombreFini(t) then return nil end

    local premier, dernier = samples[1], samples[#samples]
    if not estNombreFini(premier.t) or not estNombreFini(dernier.t) then return nil end

    -- Cas d'un seul échantillon : simple copie, sans interpolation.
    if #samples == 1 then return copier(premier) end

    -- Bornage de l'instant demandé aux limites de la liste.
    local instant = t
    if instant < premier.t then instant = premier.t end
    if instant > dernier.t then instant = dernier.t end
    if instant == dernier.t then return copier(dernier) end

    -- Recherche des deux échantillons encadrants : avant.t <= instant <= apres.t.
    local avant, apres = premier, dernier
    for i = 1, #samples - 1 do
        local courant, suivant = samples[i], samples[i + 1]
        if estNombreFini(courant.t) and estNombreFini(suivant.t)
            and courant.t <= instant and instant <= suivant.t then
            avant, apres = courant, suivant
            break
        end
    end

    local ecart = apres.t - avant.t
    local alpha = 0
    if ecart > 0 then alpha = (instant - avant.t) / ecart end

    local sortie = copier(avant)
    sortie.t = instant

    -- Interpolation linéaire des positions.
    sortie.x = avant.x + (apres.x - avant.x) * alpha
    sortie.y = avant.y + (apres.y - avant.y) * alpha
    sortie.z = avant.z + (apres.z - avant.z) * alpha
    sortie.cx = avant.cx + (apres.cx - avant.cx) * alpha
    sortie.cy = avant.cy + (apres.cy - avant.cy) * alpha
    sortie.cz = avant.cz + (apres.cz - avant.cz) * alpha

    -- Interpolation angulaire par le plus court chemin, dans [0, 360).
    sortie.h = interpolerAngle(avant.h, apres.h, alpha)
    sortie.rx = interpolerAngle(avant.rx, apres.rx, alpha)
    sortie.ry = interpolerAngle(avant.ry, apres.ry, alpha)
    sortie.rz = interpolerAngle(avant.rz, apres.rz, alpha)

    -- w, a, s et v viennent de l'échantillon précédent (déjà copié plus haut).
    return sortie
end
