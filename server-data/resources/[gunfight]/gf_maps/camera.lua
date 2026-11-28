-- Caméra orbitale de l'éditeur de maps : angle de vue (cap et inclinaison),
-- position autour du point visé et déplacement relatif à l'orientation.
--
-- Module pur (aucune native FiveM) : testé hors du jeu par
-- tests/lua/maps_camera_test.lua. Les vecteurs sont des tables ou des vector3,
-- seuls leurs champs x, y et z sont lus. Les angles sont en degrés et suivent
-- la convention de SetCamRot (ordre 2) : pitch négatif vers le bas, yaw
-- croissant dans le sens inverse des aiguilles d'une montre, 0 = nord (+y).

GFMapsCamera = {}

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function wrapYaw(yaw)
    local w = yaw % 360.0
    if w >= 360.0 then w = 0.0 end
    return w
end

-- Vue neuve : tout droit vers le bas, orientée nord (l'ancienne caméra fixe).
function GFMapsCamera.new(cfg)
    return { pitch = cfg.pitchTopDeg, yaw = 0.0 }
end

function GFMapsCamera.reset(view, cfg)
    view.pitch = cfg.pitchTopDeg
    view.yaw = 0.0
    return view
end

-- Molette maintenue + glisser, en pixels : à droite, la vue tourne vers la
-- droite (yaw diminue) ; vers le haut, la caméra se relève vers l'horizon
-- (pitch augmente), comme un regard à la souris. Bornée entre la vue du
-- dessus et l'inclinaison maximale.
function GFMapsCamera.drag(view, dxPx, dyPx, cfg)
    if not finite(dxPx) or not finite(dyPx) then return view end
    view.yaw = wrapYaw(view.yaw - dxPx * cfg.dragDegPerPx)
    view.pitch = clamp(view.pitch - dyPx * cfg.dragDegPerPx, cfg.pitchTopDeg, cfg.pitchMinDeg)
    return view
end

local STEPS = {
    left = function(view, cfg) view.yaw = wrapYaw(view.yaw + cfg.stepYawDeg) end,
    right = function(view, cfg) view.yaw = wrapYaw(view.yaw - cfg.stepYawDeg) end,
    tilt = function(view, cfg)
        view.pitch = clamp(view.pitch + cfg.stepPitchDeg, cfg.pitchTopDeg, cfg.pitchMinDeg)
    end,
    flat = function(view, cfg)
        view.pitch = clamp(view.pitch - cfg.stepPitchDeg, cfg.pitchTopDeg, cfg.pitchMinDeg)
    end,
    top = function(view, cfg) GFMapsCamera.reset(view, cfg) end,
}

-- Boutons du panneau. Renvoie false pour une action inconnue (rien ne change).
function GFMapsCamera.step(view, action, cfg)
    local apply = type(action) == 'string' and STEPS[action] or nil
    if not apply then return false end
    apply(view, cfg)
    return true
end

-- Direction du regard pour un pitch et un yaw, comme GetCamRot les donne.
function GFMapsCamera.forward(pitchDeg, yawDeg)
    local p, y = math.rad(pitchDeg), math.rad(yawDeg)
    return { x = -math.sin(y) * math.cos(p), y = math.cos(y) * math.cos(p), z = math.sin(p) }
end

-- Position de la caméra : `distance` mètres en arrière du point visé, le long
-- du regard. En vue du dessus, la caméra est donc `distance` mètres au-dessus.
function GFMapsCamera.position(target, distance, view)
    local f = GFMapsCamera.forward(view.pitch, view.yaw)
    return {
        x = target.x - f.x * distance,
        y = target.y - f.y * distance,
        z = target.z - f.z * distance,
    }
end

-- Altitude de la caméra relevée pour rester `clearance` mètres au-dessus du
-- sol sous elle. Sol inconnu (non chargé) : altitude inchangée.
function GFMapsCamera.aboveGround(camZ, groundZ, clearance)
    if not finite(groundZ) then return camZ end
    return math.max(camZ, groundZ + clearance)
end

-- Déplacement au sol pour les touches de marche, relatif au cap : `lr` > 0 à
-- droite, `ud` < 0 en avant (valeurs des contrôles 30 et 31 de GTA).
function GFMapsCamera.move(lr, ud, speed, yawDeg)
    local y = math.rad(yawDeg)
    local fx, fy = -math.sin(y), math.cos(y)   -- avant, à plat
    local rx, ry = math.cos(y), math.sin(y)    -- droite, à plat
    local forward = -ud * speed
    local right = lr * speed
    return fx * forward + rx * right, fy * forward + ry * right
end
