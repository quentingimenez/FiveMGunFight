-- =============================================================================
--  Tests unitaires de la géométrie du fond du lobby (gf_lobby/backdrop.lua).
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/lobby_backdrop.lua
--  Le module est pur : aucune native FiveM, les vecteurs sont des tables x/y/z.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/lobby_backdrop%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

dofile(racineDuDepot() .. '/server-data/resources/[gunfight]/gf_lobby/backdrop.lua')

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

local EPS = 1e-6

local function proche(attendu, obtenu, message)
    if math.abs(attendu - obtenu) > EPS then
        error(('%s : attendu %.6f, obtenu %.6f'):format(message, attendu, obtenu), 2)
    end
end

local function vrai(valeur, message)
    if not valeur then error(message, 2) end
end

local function v(x, y, z) return { x = x, y = y, z = z } end
local function sub(a, b) return v(a.x - b.x, a.y - b.y, a.z - b.z) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function cross(a, b)
    return v(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end
local function len(a) return math.sqrt(dot(a, a)) end
local function unit(a) local l = len(a) return v(a.x / l, a.y / l, a.z / l) end

-- Caméra du créateur : 4,2 m devant le ped, 1,45 m de haut, regard à 0,95 m.
local CAM = v(0.0, -4.2, 1001.45)
local LOOK = v(0.0, 0.0, 1000.95)
local FEET = v(0.0, 0.0, 1000.0)
local FOV, ASPECT, DEPTH, MARGIN = 40.0, 16 / 9, 1.0, 1.1

local function quadParDefaut()
    return GFLobbyBackdrop.quad(CAM, LOOK, FOV, ASPECT, FEET, DEPTH, MARGIN)
end

local function centre(q)
    return v(
        (q.topLeft.x + q.bottomRight.x) / 2,
        (q.topLeft.y + q.bottomRight.y) / 2,
        (q.topLeft.z + q.bottomRight.z) / 2
    )
end

verifier('fond : plan perpendiculaire à l\'axe, derrière la cible', function()
    local q = quadParDefaut()
    vrai(q, 'quad nil')
    local axe = unit(sub(LOOK, CAM))
    local profondeurCible = dot(sub(FEET, CAM), axe)
    for _, nom in ipairs({ 'topLeft', 'topRight', 'bottomRight', 'bottomLeft' }) do
        proche(profondeurCible + DEPTH, dot(sub(q[nom], CAM), axe), 'profondeur de ' .. nom)
    end
end)

verifier('fond : centre du plan sur l\'axe de la caméra', function()
    local q = quadParDefaut()
    local axe = unit(sub(LOOK, CAM))
    local ecart = cross(sub(centre(q), CAM), axe)
    proche(0.0, len(ecart), 'distance du centre à l\'axe')
end)

verifier('fond : le plan couvre tout le champ, marge comprise', function()
    local q = quadParDefaut()
    local axe = unit(sub(LOOK, CAM))
    local distance = dot(sub(FEET, CAM), axe) + DEPTH
    local demiHauteur = distance * math.tan(math.rad(FOV) / 2)
    proche(demiHauteur * MARGIN, len(sub(q.topLeft, q.bottomLeft)) / 2, 'demi-hauteur')
    proche(demiHauteur * MARGIN * ASPECT, len(sub(q.topRight, q.topLeft)) / 2, 'demi-largeur')
end)

verifier('fond : haut de l\'image en haut, droite à droite de la caméra', function()
    local q = quadParDefaut()
    vrai(q.topLeft.z > q.bottomLeft.z, 'le haut est sous le bas')
    vrai(q.topRight.z > q.bottomRight.z, 'le haut est sous le bas (droite)')
    -- Caméra tournée vers +y (nord) : sa droite est +x (est).
    vrai(q.topRight.x > q.topLeft.x, 'image inversée gauche/droite')
    vrai(q.bottomRight.x > q.bottomLeft.x, 'image inversée gauche/droite (bas)')
end)

verifier('fond : triangles visibles depuis la caméra, image non retournée', function()
    local q = quadParDefaut()
    local triangles = GFLobbyBackdrop.triangles(q)
    vrai(#triangles == 2, 'deux triangles attendus, obtenu ' .. #triangles)
    for i, t in ipairs(triangles) do
        local a, b, c = t[1], t[2], t[3]
        -- DRAW_TEXTURED_POLY ne dessine que la face vers laquelle pointe
        -- (b - a) x (c - a) : elle doit pointer vers la caméra.
        local normale = cross(sub(b.p, a.p), sub(c.p, a.p))
        vrai(dot(normale, sub(CAM, a.p)) > 0, 'triangle ' .. i .. ' tourné dos à la caméra')
        for _, s in ipairs(t) do
            local attenduU = (s.p == q.topLeft or s.p == q.bottomLeft) and 0.0 or 1.0
            local attenduV = (s.p == q.topLeft or s.p == q.topRight) and 0.0 or 1.0
            proche(attenduU, s.u, 'u du triangle ' .. i)
            proche(attenduV, s.v, 'v du triangle ' .. i)
        end
    end
end)

verifier('fond : les deux triangles recouvrent tout le plan', function()
    local q = quadParDefaut()
    local vus = {}
    for _, t in ipairs(GFLobbyBackdrop.triangles(q)) do
        local diagonale = 0
        for _, s in ipairs(t) do
            vus[s.p] = true
            if s.p == q.topLeft or s.p == q.bottomRight then diagonale = diagonale + 1 end
        end
        vrai(diagonale == 2, 'chaque triangle doit s\'appuyer sur la diagonale haut-gauche/bas-droite')
    end
    for _, nom in ipairs({ 'topLeft', 'topRight', 'bottomRight', 'bottomLeft' }) do
        vrai(vus[q[nom]], 'coin non couvert : ' .. nom)
    end
end)

verifier('fond : caméra plongeante, plan toujours face à la caméra', function()
    local cam = v(3.0, -3.0, 1003.0)
    local q = GFLobbyBackdrop.quad(cam, FEET, FOV, ASPECT, FEET, DEPTH, MARGIN)
    vrai(q, 'quad nil')
    local axe = unit(sub(FEET, cam))
    local profondeur = dot(sub(FEET, cam), axe) + DEPTH
    for _, nom in ipairs({ 'topLeft', 'topRight', 'bottomRight', 'bottomLeft' }) do
        proche(profondeur, dot(sub(q[nom], cam), axe), 'profondeur de ' .. nom)
    end
    vrai(q.topLeft.z > q.bottomLeft.z, 'le haut est sous le bas')
end)

verifier('fond : caméra sans direction utilisable refusée', function()
    vrai(GFLobbyBackdrop.quad(CAM, CAM, FOV, ASPECT, FEET, DEPTH, MARGIN) == nil, 'caméra sans direction acceptée')
    local dessus = v(0.0, 0.0, 1010.0)
    vrai(GFLobbyBackdrop.quad(dessus, FEET, FOV, ASPECT, FEET, DEPTH, MARGIN) == nil, 'caméra verticale acceptée')
end)

verifier('fond : cible derrière la caméra refusée', function()
    local cible = v(0.0, -10.0, 1000.0)
    vrai(GFLobbyBackdrop.quad(CAM, LOOK, FOV, ASPECT, cible, DEPTH, MARGIN) == nil, 'plan placé derrière la caméra')
end)

verifier('fond : plan à distance nulle de la caméra refusé', function()
    -- Plan dans l'objectif : ses quatre coins seraient confondus.
    vrai(GFLobbyBackdrop.quad(CAM, LOOK, FOV, ASPECT, CAM, 0.0, MARGIN) == nil, 'plan dégénéré accepté')
end)

-- Projection d'un point en hauteur d'écran (0 en haut, 1 en bas), modèle sténopé
-- indépendant du module : même caméra que le jeu, FOV vertical.
local function ecranY(cam, look, fov, p)
    local f = unit(sub(look, cam))
    local r = unit(cross(f, v(0.0, 0.0, 1.0)))
    local u = cross(r, f)
    local d = sub(p, cam)
    return 0.5 - dot(d, u) / (2.0 * dot(d, f) * math.tan(math.rad(fov) / 2.0))
end

local FLOOR_V = 0.775

verifier('sol : hauteur à l\'écran d\'une ligne de l\'image', function()
    proche(0.5 + 0.275 * 1.1, GFLobbyBackdrop.floorScreenY(FLOOR_V, 1.1), 'ligne de sol, marge 10 %')
    proche(0.5, GFLobbyBackdrop.floorScreenY(0.5, 1.3), 'milieu de l\'image au milieu de l\'écran')
end)

verifier('sol : la ligne de sol du fond est dessinée à floorScreenY', function()
    local q = quadParDefaut()
    local gauche = sub(q.bottomLeft, q.topLeft)
    local p = v(q.topLeft.x + gauche.x * FLOOR_V, q.topLeft.y + gauche.y * FLOOR_V,
        q.topLeft.z + gauche.z * FLOOR_V)
    proche(GFLobbyBackdrop.floorScreenY(FLOOR_V, MARGIN), ecranY(CAM, LOOK, FOV, p), 'ligne de sol projetée')
end)

verifier('regard : les pieds tombent sur la ligne de sol', function()
    local cible = GFLobbyBackdrop.floorScreenY(FLOOR_V, MARGIN)
    -- Créateur, lobby à 1 membre, lobby à 4 membres (distance 4,4 + 3 × 0,95).
    for _, cas in ipairs({ { 1.45, 4.2, 40.0 }, { 1.52, 4.4, 42.0 }, { 1.52, 7.25, 42.0 } }) do
        local hauteur, distance, fov = cas[1], cas[2], cas[3]
        local regard = GFLobbyBackdrop.lookHeight(hauteur, distance, fov, cible)
        vrai(regard, 'regard nil')
        local cam = v(0.0, -distance, hauteur)
        proche(cible, ecranY(cam, v(0.0, 0.0, regard), fov, v(0.0, 0.0, 0.0)),
            ('pieds à l\'écran (h=%.2f, d=%.2f)'):format(hauteur, distance))
    end
end)

verifier('regard : pieds au centre si la ligne est à mi-hauteur', function()
    proche(0.0, GFLobbyBackdrop.lookHeight(1.52, 4.4, 42.0, 0.5), 'regard sur les pieds')
end)

verifier('regard : distance nulle ou négative refusée', function()
    vrai(GFLobbyBackdrop.lookHeight(1.52, 0.0, 42.0, 0.8) == nil, 'distance nulle acceptée')
    vrai(GFLobbyBackdrop.lookHeight(1.52, -1.0, 42.0, 0.8) == nil, 'distance négative acceptée')
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
