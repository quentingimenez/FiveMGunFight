-- =============================================================================
--  gf_core - RATE LIMIT (module serveur pur)
--  Fenêtre glissante simple, sans native : `maintenant` est injecté pour que
--  les tests puissent avancer l'horloge sans attendre.
-- =============================================================================

RateLimit = {}

local function estNombreFini(valeur)
    return type(valeur) == 'number' and valeur == valeur and valeur ~= math.huge and valeur ~= -math.huge
end

--- Autorise une action pour `cle` si elle n'a pas dépassé `max` occurrences
--- dans la fenêtre de `fenetre_ms` millisecondes.
---
--- L'état est une table mutable gérée par l'appelant (une table par usage).
--- `maintenant` est fourni par l'appelant (GetGameTimer() côté serveur).
---
--- Retourne true si l'action est autorisée, false sinon.
function RateLimit.autoriser(etat, cle, max, fenetre_ms, maintenant)
    if type(etat) ~= 'table' or cle == nil then return false end
    if not estNombreFini(max) or max < 1 then return false end
    if not estNombreFini(fenetre_ms) or fenetre_ms <= 0 then return false end
    if not estNombreFini(maintenant) then return false end

    -- On conserve les horodatages encore dans la fenêtre. Une horloge qui
    -- recule (redémarrage) jette les entrées du futur : l'état repart propre.
    local anciennes = etat[cle]
    local recentes = {}
    if type(anciennes) == 'table' then
        for _, instant in ipairs(anciennes) do
            if estNombreFini(instant) and instant <= maintenant and (maintenant - instant) < fenetre_ms then
                recentes[#recentes + 1] = instant
            end
        end
    end

    if #recentes >= max then
        etat[cle] = recentes
        return false
    end

    recentes[#recentes + 1] = maintenant
    etat[cle] = recentes
    return true
end

--- Efface l'état d'une clé (déconnexion d'un joueur, par exemple).
function RateLimit.oublier(etat, cle)
    if type(etat) == 'table' then etat[cle] = nil end
end
