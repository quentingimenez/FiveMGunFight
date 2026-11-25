-- =============================================================================
--  gf_core - VALIDATION (module serveur pur)
--  Aucune native FiveM ici : server.lua injecte les accès au monde via `deps`,
--  ce qui permet de tester ces règles avec un simple interpréteur Lua.
-- =============================================================================

Validation = {}

local function estNombreFini(valeur)
    return type(valeur) == 'number' and valeur == valeur and valeur ~= math.huge and valeur ~= -math.huge
end

--- Normalise un identifiant réseau (netId) de véhicule.
--- Accepte uniquement un entier strictement positif :
---   * nombre entier (1, 42) ou flottant entier (42.0) ;
---   * chaîne composée uniquement de chiffres ("42").
--- Refuse nil, 0, les négatifs, les décimaux (12.5), NaN, l'infini, les
--- chaînes non numériques, les booléens et les tables.
--- @param valeur any
--- @return integer|nil
function Validation.normaliserNetId(valeur)
    local nombre
    if type(valeur) == 'number' then
        nombre = valeur
    elseif type(valeur) == 'string' then
        if not valeur:match('^%d+$') then return nil end
        nombre = tonumber(valeur)
    else
        return nil
    end

    if not nombre or not estNombreFini(nombre) then return nil end
    local entier = math.tointeger(nombre)
    if not entier or entier <= 0 then return nil end
    return entier
end

local function coordonnees(valeur)
    -- En jeu, GetEntityCoords renvoie un vector3 ; les tests utilisent une table.
    if type(valeur) ~= 'table' and type(valeur) ~= 'vector3' then return nil end
    local x, y, z = valeur.x, valeur.y, valeur.z
    if not (estNombreFini(x) and estNombreFini(y) and estNombreFini(z)) then return nil end
    return x, y, z
end

--- Distance euclidienne entre deux positions { x, y, z } (ou vector3 FiveM).
--- Retourne nil si l'une des positions est invalide.
--- @return number|nil
function Validation.distance(a, b)
    local ax, ay, az = coordonnees(a)
    local bx, by, bz = coordonnees(b)
    if not ax or not bx then return nil end

    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Vérifie qu'un netId de véhicule peut être rattaché au joueur `src`.
---
--- `deps` fournit les natives (voir server.lua) :
---   entityFromNetId(netId) -> entity
---   entityExists(entity)   -> boolean
---   entityType(entity)     -> integer (2 = véhicule)
---   entityOwner(entity)    -> integer (propriétaire réseau, -1 si aucun)
---   entityCoords(entity)   -> { x, y, z }
---   playerCoords(src)      -> { x, y, z }
---   maxDistance            -> number (mètres)
---
--- Retourne (ok, raison, netIdNormalise). Quand ok vaut false, `raison` dit
--- pourquoi : 'deps', 'netId', 'joueur', 'introuvable', 'type',
--- 'proprietaire', 'position' ou 'distance'.
function Validation.verifierVehicule(netId, src, deps)
    if type(deps) ~= 'table' then return false, 'deps', nil end
    for _, nom in ipairs({
        'entityFromNetId',
        'entityExists',
        'entityType',
        'entityOwner',
        'entityCoords',
        'playerCoords',
    }) do
        if type(deps[nom]) ~= 'function' then return false, 'deps', nil end
    end

    local id = Validation.normaliserNetId(netId)
    if not id then return false, 'netId', nil end

    local joueur = math.tointeger(src)
    if not joueur or joueur <= 0 then return false, 'joueur', nil end

    local entite = deps.entityFromNetId(id)
    if not entite or entite == 0 or not deps.entityExists(entite) then return false, 'introuvable', nil end

    if deps.entityType(entite) ~= 2 then return false, 'type', nil end
    if deps.entityOwner(entite) ~= joueur then return false, 'proprietaire', nil end

    local distance = Validation.distance(deps.entityCoords(entite), deps.playerCoords(joueur))
    if not distance then return false, 'position', nil end

    local maximum = tonumber(deps.maxDistance)
    if not estNombreFini(maximum) or maximum <= 0 then return false, 'distance', nil end
    if distance > maximum then return false, 'distance', nil end

    return true, 'ok', id
end

--- Dérive le tueur à créditer à partir du dernier dégât vu par le serveur.
---
--- `entree` = { src = tireur, at = GetGameTimer(), weapon = hash } ou nil.
--- Le kill n'est crédité que si :
---   * le dégât a moins de `fenetre_ms` millisecondes ;
---   * le tireur est dans le même mode (`meme_mode`) ;
---   * le tireur n'est pas la victime.
---
--- Retourne (src, arme) ou (nil, nil).
function Validation.tueurCreditable(entree, maintenant, fenetre_ms, meme_mode, victime)
    if type(entree) ~= 'table' then return nil, nil end
    if not estNombreFini(maintenant) or not estNombreFini(entree.at) then return nil, nil end

    local tireur = math.tointeger(entree.src)
    if not tireur or tireur <= 0 or tireur == victime then return nil, nil end

    local fenetre = tonumber(fenetre_ms)
    if not estNombreFini(fenetre) or fenetre <= 0 then return nil, nil end

    local ecoule = maintenant - entree.at
    -- Une horloge qui recule (redémarrage) invalide l'entrée ; la fenêtre est
    -- stricte : à exactement `fenetre_ms`, le dégât n'est plus crédité.
    if ecoule < 0 or ecoule >= fenetre then return nil, nil end
    if not meme_mode then return nil, nil end

    return tireur, entree.weapon
end

--- Vérifie côté serveur que la victime est réellement morte.
---
--- `deps` = {
---   ped = function(src) -> entity,
---   health = function(entity) -> number,
---   dead = function(entity) -> boolean  (facultatif),
--- }
--- La native `dead` est testée en premier : selon la version de FXServer, la
--- santé du ped peut encore être positive au moment où l'événement de mort
--- arrive. Si elle est absente ou échoue, la santé reste le critère de repli.
--- Retourne (ok, raison) ; `raison` vaut 'mort' quand ok vaut true.
function Validation.mortConfirmee(victime, deps)
    local joueur = math.tointeger(victime)
    if not joueur or joueur <= 0 then return false, 'joueur' end
    if type(deps) ~= 'table' or type(deps.ped) ~= 'function' or type(deps.health) ~= 'function' then
        return false, 'deps'
    end

    local ped = deps.ped(joueur)
    if not ped or ped == 0 then return false, 'ped' end

    if type(deps.dead) == 'function' then
        local ok, mort = pcall(deps.dead, ped)
        if ok and mort == true then return true, 'mort' end
    end

    local sante = deps.health(ped)
    if not estNombreFini(sante) then return false, 'sante' end
    if sante > 0 then return false, 'vivant' end

    return true, 'mort'
end
