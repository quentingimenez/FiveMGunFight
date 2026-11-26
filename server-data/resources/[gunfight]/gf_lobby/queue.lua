-- =============================================================================
--  gf_lobby - FILE D'ATTENTE DES ESCOUADES (module pur)
--  Gère l'ordre d'arrivée des escouades en attente d'un match. Aucune native
--  FiveM, aucune horloge : l'ordre vient d'un compteur interne incrémenté à
--  chaque inscription. Le fichier peut être chargé dans un bac à sable : il
--  ne crée qu'un seul global, LobbyQueue.
-- =============================================================================

-- luacheck: globals LobbyQueue
LobbyQueue = {}

local Q = LobbyQueue

-- Crée une file vide. entries[partyId] = { mode = 'attack', order = n }.
function Q.new()
    return { entries = {}, seq = 0 }
end

-- Inscrit une escouade. Renvoie false si elle est déjà présente, sans toucher
-- à son ordre d'arrivée. Une réinscription après leave() prend un nouvel ordre.
function Q.join(q, partyId, mode)
    if not q or not q.entries or q.entries[partyId] then return false end
    q.seq = q.seq + 1
    q.entries[partyId] = { mode = mode or 'attack', order = q.seq }
    return true
end

-- Retire une escouade de la file. Renvoie false si elle n'y était pas.
function Q.leave(q, partyId)
    if not q or not q.entries or not q.entries[partyId] then return false end
    q.entries[partyId] = nil
    return true
end

-- Dit si une escouade est inscrite.
function Q.has(q, partyId)
    return q ~= nil and q.entries ~= nil and q.entries[partyId] ~= nil
end

-- Compare deux escouades pour le tri d'après leur ordre d'arrivée. En cas
-- d'égalité (ne devrait pas arriver), l'identifiant départage pour garder un
-- tri total et déterministe. Les ordres sont conservés à part, dans `orders`.
local function makeComparator(orders)
    return function(a, b)
        local oa, ob = orders[a.partyId], orders[b.partyId]
        if oa == ob then return a.partyId < b.partyId end
        return oa < ob
    end
end

-- Liste des escouades prêtes, triées par ordre croissant. Chaque élément est
-- { partyId = id, members = { src... } } avec une copie des membres : ni
-- parties ni les listes de membres ne sont modifiées. Une escouade est prête
-- si elle existe, a au moins un membre, n'est pas en train de lancer, et si
-- tous ses membres sont éligibles. Une entrée dont l'escouade a disparu de
-- parties est retirée de la file.
function Q.ready(q, parties, isEligible)
    local ready = {}

    if not q or not q.entries or type(parties) ~= 'table' then return ready end

    -- On collecte d'abord les entrées valides pour pouvoir purger les
    -- escouades disparues sans perturber le parcours.
    local stale = {}
    local orders = {}
    for partyId, entry in pairs(q.entries) do
        local party = parties[partyId]
        if type(party) ~= 'table' then
            stale[#stale + 1] = partyId
        else
            local members = party.members
            if type(members) == 'table' and #members >= 1 and party.launching ~= true then
                local eligible = true
                for _, src in ipairs(members) do
                    if not isEligible(src) then
                        eligible = false
                        break
                    end
                end
                if eligible then
                    local copied = {}
                    for i, src in ipairs(members) do copied[i] = src end
                    ready[#ready + 1] = {
                        partyId = partyId,
                        members = copied,
                    }
                    orders[partyId] = entry.order
                end
            end
        end
    end

    for _, partyId in ipairs(stale) do q.entries[partyId] = nil end

    table.sort(ready, makeComparator(orders))
    return ready
end

-- Nombre total de joueurs dans les escouades prêtes. Réutilise ready() pour
-- ne compter que celles qui sont réellement prêtes.
function Q.count(q, parties, isEligible)
    local total = 0
    for _, squad in ipairs(Q.ready(q, parties, isEligible)) do
        total = total + #squad.members
    end
    return total
end

-- Choisit dans la liste triée un ensemble d'escouades entières : on ajoute une
-- escouade si elle tient sous `max`, sinon on la saute et on continue. Renvoie
-- nil si le total reste sous `min`. Une escouade n'est jamais coupée et la
-- liste d'entrée n'est pas modifiée.
function Q.pick(readyList, min, max)
    if type(readyList) ~= 'table' then return nil end

    local chosen = {}
    local total = 0
    for _, squad in ipairs(readyList) do
        local size = #squad.members
        if total + size <= max then
            chosen[#chosen + 1] = squad
            total = total + size
        end
    end

    if total < min then return nil end
    return chosen
end
