-- =============================================================================
--  gf_ui - PILE DE CALQUES NUI (module pur)
--  Possède la pile des calques ouverts par les autres ressources. Aucune native
--  FiveM, aucune horloge, aucun accès fichier : le fichier peut être chargé dans
--  un bac à sable et ne crée qu'un seul global, Layers.
-- =============================================================================

-- luacheck: globals Layers
Layers = {}

local L = Layers

-- Un nom valide est une chaîne non vide.
local function valid(nom)
    return type(nom) == 'string' and nom ~= ''
end

-- Crée une pile vide : order est l'ordre d'empilement, pos associe un nom à
-- son index dans order (les index sont recalculés après un pop au milieu).
function L.new()
    -- La métatable donne à chaque pile ses méthodes via `:` (push, pop, ...).
    return setmetatable({ order = {}, pos = {} }, { __index = L })
end

-- Ajoute un nom en haut de la pile. Un doublon ne déplace pas le calque déjà
-- présent et ne change pas la pile. Renvoie true seulement si elle a changé.
function L.push(stack, nom)
    if not valid(nom) or not stack or not stack.order or not stack.pos then return false end
    if stack.pos[nom] ~= nil then return false end
    local index = #stack.order + 1
    stack.order[index] = nom
    stack.pos[nom] = index
    return true
end

-- Retire un nom où qu'il soit dans la pile, en décalant les index des calques
-- situés au-dessus. Renvoie true seulement si le nom était présent.
function L.pop(stack, nom)
    if not valid(nom) or not stack or not stack.order or not stack.pos then return false end
    local index = stack.pos[nom]
    if index == nil then return false end
    table.remove(stack.order, index)
    stack.pos[nom] = nil
    for i = index, #stack.order do
        stack.pos[stack.order[i]] = i
    end
    return true
end

-- Nombre de calques empilés.
function L.count(stack)
    return stack and stack.order and #stack.order or 0
end

-- Nom du calque au sommet, ou nil si la pile est vide.
function L.top(stack)
    if not stack or not stack.order then return nil end
    return stack.order[#stack.order]
end

-- Dit si un nom est présent dans la pile.
function L.has(stack, nom)
    if not valid(nom) or not stack or not stack.pos then return false end
    return stack.pos[nom] ~= nil
end
