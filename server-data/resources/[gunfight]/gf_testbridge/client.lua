-- Passerelle de test NUI : exécute les demandes de la console côté client,
-- puis rapporte l'état des calques au serveur sous forme de ligne de journal.

local enCours = false

-- Lit l'état des calques possédés par gf_ui.
local function etatCalques()
    local etat = exports.gf_ui:GetLayers() or { count = 0, top = nil }
    return etat.count or 0, etat.top
end

RegisterNetEvent('gf_testbridge:demande', function(demande)
    if type(demande) ~= 'table' then return end
    local page, action = demande.page, demande.action
    if not GfTestbridge.estPage(page) then return end
    if action ~= 'open' and action ~= 'close' and action ~= 'status' then return end
    if enCours then return end
    enCours = true

    -- Jamais de Wait dans le handler réseau : tout se passe dans un fil dédié.
    CreateThread(function()
        local calques, sommet = etatCalques()
        local etat, detail

        if action == 'status' then
            etat = (calques == 0) and 'ferme' or 'ouvert'
        elseif action == 'open' then
            if calques > 0 then
                etat = 'refus'
                detail = 'un calque est déjà ouvert'
            else
                ExecuteCommand(GfTestbridge.commande(page))
                Wait(1500)
                calques, sommet = etatCalques()
                if calques > 0 and sommet == page then
                    etat = 'ouvert'
                else
                    etat = 'echec'
                    detail = 'page non ouverte'
                end
            end
        else
            TriggerEvent('gf_testbridge:fermer', page)
            Wait(700)
            calques, sommet = etatCalques()
            if calques == 0 then
                etat = 'ferme'
            else
                etat = 'echec'
                detail = 'calques restants'
            end
        end

        enCours = false
        TriggerServerEvent('gf_testbridge:rapport', {
            page = page,
            action = action,
            etat = etat,
            calques = calques,
            sommet = sommet or 'aucun',
            detail = detail,
        })
    end)
end)

-- Prévenir le serveur dès qu'un joueur est réellement en jeu.
CreateThread(function()
    while true do
        Wait(1000)
        if NetworkIsSessionStarted() and IsPlayerPlaying(PlayerId()) then
            TriggerServerEvent('gf_testbridge:clientPret')
            break
        end
    end
end)
