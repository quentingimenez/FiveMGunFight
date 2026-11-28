-- =============================================================================
--  Tests unitaires de la caméra de l'éditeur de maps (gf_maps/camera.lua).
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/maps_camera_test.lua
--  Le module est pur : aucune native FiveM, les vecteurs sont des tables x/y/z.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/maps_camera_test%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()
local RESSOURCE = RACINE .. '/server-data/resources/[gunfight]/gf_maps/'
dofile(RESSOURCE .. 'config.lua')
dofile(RESSOURCE .. 'camera.lua')

local Cam = GFMapsCamera
local CFG = Config.EditorCamera

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

local function proche(attendu, obtenu, message, eps)
    if type(obtenu) ~= 'number' or obtenu ~= obtenu or math.abs(attendu - obtenu) > (eps or EPS) then
        error(('%s : attendu %.6f, obtenu %s'):format(message, attendu, tostring(obtenu)), 2)
    end
end

local function vrai(valeur, message)
    if not valeur then error(message, 2) end
end

local function v(x, y, z) return { x = x, y = y, z = z } end

-- ------------------------------------------------------------------ Configuration
verifier('la configuration borne une inclinaison qui reste sous l\'horizon', function()
    vrai(type(CFG) == 'table', 'Config.EditorCamera absente')
    vrai(CFG.pitchTopDeg < 0 and CFG.pitchTopDeg > -90, 'vue du dessus hors de ]-90, 0[')
    vrai(CFG.pitchMinDeg < 0 and CFG.pitchMinDeg > CFG.pitchTopDeg, 'inclinaison maximale incohérente')
    vrai(CFG.dragDegPerPx > 0 and CFG.stepYawDeg > 0 and CFG.stepPitchDeg > 0, 'pas nuls ou négatifs')
    vrai(CFG.groundClearanceM >= 0, 'marge au sol négative')
end)

-- ------------------------------------------------------------------ État initial
verifier('une vue neuve regarde tout droit vers le bas, orientée nord', function()
    local vue = Cam.new(CFG)
    proche(CFG.pitchTopDeg, vue.pitch, 'pitch')
    proche(0.0, vue.yaw, 'yaw')
end)

verifier('reset revient à la vue du dessus depuis n\'importe quel angle', function()
    local vue = { pitch = -40.0, yaw = 210.0 }
    Cam.reset(vue, CFG)
    proche(CFG.pitchTopDeg, vue.pitch, 'pitch')
    proche(0.0, vue.yaw, 'yaw')
end)

-- ------------------------------------------------------------------ Glisser
verifier('glisser à droite tourne la vue dans le sens horaire (yaw diminue)', function()
    local vue = Cam.new(CFG)
    Cam.drag(vue, 100, 0, CFG)
    proche((360.0 - 100 * CFG.dragDegPerPx) % 360.0, vue.yaw, 'yaw')
    proche(CFG.pitchTopDeg, vue.pitch, 'pitch inchangé')
end)

verifier('glisser vers le haut incline la caméra, sans dépasser le maximum', function()
    local vue = Cam.new(CFG)
    Cam.drag(vue, 0, -50, CFG)
    proche(CFG.pitchTopDeg + 50 * CFG.dragDegPerPx, vue.pitch, 'pitch après 50 px')
    Cam.drag(vue, 0, -100000, CFG)
    proche(CFG.pitchMinDeg, vue.pitch, 'pitch borné à l\'inclinaison maximale')
end)

verifier('glisser vers le bas ne dépasse jamais la vue du dessus', function()
    local vue = Cam.new(CFG)
    Cam.drag(vue, 0, 100000, CFG)
    proche(CFG.pitchTopDeg, vue.pitch, 'pitch borné à la vue du dessus')
end)

verifier('le yaw reste dans [0, 360[ après plusieurs tours', function()
    local vue = Cam.new(CFG)
    for _ = 1, 50 do Cam.drag(vue, -997, 0, CFG) end
    vrai(vue.yaw >= 0.0 and vue.yaw < 360.0, 'yaw hors bornes : ' .. tostring(vue.yaw))
    for _ = 1, 50 do Cam.drag(vue, 1013, 0, CFG) end
    vrai(vue.yaw >= 0.0 and vue.yaw < 360.0, 'yaw hors bornes : ' .. tostring(vue.yaw))
end)

verifier('un yaw qui arrondit à 360 est ramené à 0', function()
    -- -3e-15 % 360 vaut 360.0 en double : le cap doit rester dans [0, 360[
    local vue = Cam.new(CFG)
    Cam.drag(vue, 1e-14, 0, CFG)
    vrai(vue.yaw >= 0.0 and vue.yaw < 360.0, 'yaw hors bornes : ' .. tostring(vue.yaw))
end)

verifier('une entrée non numérique ou non finie ne change rien', function()
    local vue = { pitch = -50.0, yaw = 30.0 }
    for _, mauvais in ipairs({ 'abc', {}, true, 0 / 0, math.huge, -math.huge }) do
        Cam.drag(vue, mauvais, mauvais, CFG)
        proche(-50.0, vue.pitch, 'pitch après ' .. tostring(mauvais))
        proche(30.0, vue.yaw, 'yaw après ' .. tostring(mauvais))
    end
end)

-- ------------------------------------------------------------------ Boutons
verifier('les boutons tournent, inclinent, redressent et remettent à plat', function()
    local vue = Cam.new(CFG)
    Cam.step(vue, 'left', CFG)
    proche(CFG.stepYawDeg, vue.yaw, 'gauche')
    Cam.step(vue, 'right', CFG)
    Cam.step(vue, 'right', CFG)
    proche(360.0 - CFG.stepYawDeg, vue.yaw, 'droite')
    Cam.step(vue, 'tilt', CFG)
    proche(CFG.pitchTopDeg + CFG.stepPitchDeg, vue.pitch, 'incliner')
    Cam.step(vue, 'flat', CFG)
    proche(CFG.pitchTopDeg, vue.pitch, 'redresser')
    Cam.step(vue, 'tilt', CFG)
    Cam.step(vue, 'top', CFG)
    proche(CFG.pitchTopDeg, vue.pitch, 'vue du dessus : pitch')
    proche(0.0, vue.yaw, 'vue du dessus : yaw')
end)

verifier('une action de bouton inconnue est refusée sans rien changer', function()
    local vue = { pitch = -60.0, yaw = 90.0 }
    vrai(Cam.step(vue, 'explose', CFG) == false, 'action inconnue acceptée')
    vrai(Cam.step(vue, nil, CFG) == false, 'action nil acceptée')
    proche(-60.0, vue.pitch, 'pitch')
    proche(90.0, vue.yaw, 'yaw')
end)

-- ------------------------------------------------------------------ Géométrie
verifier('forward suit la convention de rotation de GTA (ordre 2)', function()
    local f = Cam.forward(0.0, 0.0)
    proche(0.0, f.x, 'nord x') proche(1.0, f.y, 'nord y') proche(0.0, f.z, 'nord z')
    f = Cam.forward(0.0, 90.0)
    proche(-1.0, f.x, 'yaw 90 regarde vers -x') proche(0.0, f.y, 'yaw 90 y', 1e-9)
    f = Cam.forward(-90.0, 0.0)
    proche(-1.0, f.z, 'pitch -90 regarde vers le bas')
end)

verifier('la caméra est placée à la distance demandée et vise la cible', function()
    local cible = v(100.0, -200.0, 30.0)
    for _, angle in ipairs({ { -89.9, 0.0 }, { -45.0, 30.0 }, { -25.0, 270.0 } }) do
        local vue = { pitch = angle[1], yaw = angle[2] }
        local pos = Cam.position(cible, 150.0, vue)
        local dx, dy, dz = cible.x - pos.x, cible.y - pos.y, cible.z - pos.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        proche(150.0, d, 'distance')
        local f = Cam.forward(vue.pitch, vue.yaw)
        proche(f.x, dx / d, 'visée x') proche(f.y, dy / d, 'visée y') proche(f.z, dz / d, 'visée z')
    end
end)

verifier('en vue du dessus, la caméra est au-dessus de la cible comme avant', function()
    local cible = v(10.0, 20.0, 5.0)
    local pos = Cam.position(cible, 180.0, Cam.new(CFG))
    proche(10.0, pos.x, 'x', 1e-3)
    proche(20.0, pos.y, 'y', 0.5)
    proche(5.0 + 180.0, pos.z, 'altitude', 1e-3)
end)

verifier('la caméra reste au-dessus du sol avec la marge', function()
    proche(42.0, Cam.aboveGround(42.0, 10.0, CFG.groundClearanceM), 'déjà assez haut')
    proche(30.0 + CFG.groundClearanceM, Cam.aboveGround(12.0, 30.0, CFG.groundClearanceM), 'remontée')
    proche(12.0, Cam.aboveGround(12.0, nil, CFG.groundClearanceM), 'sol inconnu : inchangé')
end)

-- ------------------------------------------------------------------ Déplacement
verifier('ZQSD vers le nord en vue orientée nord, comme avant', function()
    local dx, dy = Cam.move(0.0, -1.0, 10.0, 0.0)
    proche(0.0, dx, 'avant x') proche(10.0, dy, 'avant y')
    dx, dy = Cam.move(1.0, 0.0, 10.0, 0.0)
    proche(10.0, dx, 'droite x') proche(0.0, dy, 'droite y')
end)

verifier('ZQSD suit l\'orientation de la caméra', function()
    -- yaw 90 : la caméra regarde vers -x, sa droite est +y
    local dx, dy = Cam.move(0.0, -1.0, 10.0, 90.0)
    proche(-10.0, dx, 'avant x') proche(0.0, dy, 'avant y', 1e-9)
    dx, dy = Cam.move(1.0, 0.0, 10.0, 90.0)
    proche(0.0, dx, 'droite x', 1e-9) proche(10.0, dy, 'droite y')
end)

print(('\n%d réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
