-- Géométrie du fond du lobby : un plan texturé face à la caméra, placé juste
-- derrière la scène et assez grand pour remplir tout le champ. Vu de la
-- caméra, l'image se comporte comme un fond d'écran fixe, avec le ped devant.
--
-- Module pur (aucune native FiveM) : testé hors du jeu par
-- tests/lua/lobby_backdrop.lua. Les vecteurs sont des tables ou des vector3,
-- seuls leurs champs x, y et z sont lus.

GFLobbyBackdrop = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end
local function add(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
local function sub(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
local function scale(a, s) return vec(a.x * s, a.y * s, a.z * s) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

local function cross(a, b)
    return vec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function normalize(a)
    local length = math.sqrt(dot(a, a))
    if length < 1e-6 then return nil end
    return scale(a, 1.0 / length)
end

local WORLD_UP = vec(0.0, 0.0, 1.0)

-- Coins d'un plan perpendiculaire à l'axe de la caméra, `depthBehind` mètres
-- derrière `target` (mesuré le long de l'axe), qui couvre un champ vertical de
-- `fovDeg` degrés et un rapport largeur/hauteur `aspect`, agrandi de `margin`.
-- Traiter le FOV comme vertical surestime la largeur s'il est horizontal : le
-- plan couvre l'écran dans les deux cas.
-- Renvoie nil si la caméra n'a pas de direction, regarde à la verticale ou si
-- le plan tomberait derrière elle.
function GFLobbyBackdrop.quad(camPos, camLook, fovDeg, aspect, target, depthBehind, margin)
    local forward = normalize(sub(camLook, camPos))
    if not forward then return nil end
    local right = normalize(cross(forward, WORLD_UP))
    if not right then return nil end
    local up = cross(right, forward)

    local distance = dot(sub(target, camPos), forward) + depthBehind
    if distance <= 0.0 then return nil end

    local halfHeight = distance * math.tan(math.rad(fovDeg) / 2.0) * margin
    local halfWidth = halfHeight * aspect
    local center = add(camPos, scale(forward, distance))
    local r = scale(right, halfWidth)
    local u = scale(up, halfHeight)
    return {
        topLeft = add(sub(center, r), u),
        topRight = add(add(center, r), u),
        bottomRight = sub(add(center, r), u),
        bottomLeft = sub(sub(center, r), u),
    }
end

-- Hauteur à l'écran (0 en haut, 1 en bas) de la ligne `v` de l'image (0 en
-- haut, 1 en bas) : le plan de quad() déborde du champ de `margin`.
function GFLobbyBackdrop.floorScreenY(v, margin)
    return 0.5 + (v - 0.5) * margin
end

-- Hauteur de regard, au-dessus des pieds, qui fait apparaître les pieds à la
-- hauteur d'écran `screenY` pour une caméra placée `cameraHeight` au-dessus
-- des pieds et `distance` mètres devant eux à l'horizontale (FOV vertical).
-- Renvoie nil si la distance n'est pas positive.
function GFLobbyBackdrop.lookHeight(cameraHeight, distance, fovDeg, screenY)
    if distance <= 0.0 then return nil end
    -- Angle entre l'axe de la caméra et le rayon vers les pieds.
    local below = math.atan((screenY - 0.5) * 2.0 * math.tan(math.rad(fovDeg) / 2.0))
    local pitch = math.atan(cameraHeight / distance) - below
    return cameraHeight - distance * math.tan(pitch)
end

-- Les deux triangles du plan, avec leurs coordonnées de texture : (u, v) =
-- (0, 0) est le coin haut-gauche de l'image. DRAW_TEXTURED_POLY ne dessine que
-- la face vers laquelle pointe (b - a) x (c - a) : l'ordre des sommets la
-- tourne vers la caméra.
function GFLobbyBackdrop.triangles(q)
    local topLeft = { p = q.topLeft, u = 0.0, v = 0.0 }
    local topRight = { p = q.topRight, u = 1.0, v = 0.0 }
    local bottomRight = { p = q.bottomRight, u = 1.0, v = 1.0 }
    local bottomLeft = { p = q.bottomLeft, u = 0.0, v = 1.0 }
    return {
        { topLeft, bottomRight, topRight },
        { topLeft, bottomLeft, bottomRight },
    }
end
