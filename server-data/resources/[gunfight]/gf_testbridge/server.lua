-- Passerelle de test NUI : commande console réservée au développement.
-- La ressource n'est pas assurée par server.cfg : le pilote l'ensure par rcon.

local actif = GfTestbridgeGuard.allowed(GetConvar('gf_dev_testbridge', ''))
if not actif then
    print('[gf_testbridge] désactivé : gf_dev_testbridge doit valoir "true"')
    CreateThread(function()
        Wait(0)
        StopResource(GetCurrentResourceName())
    end)
    return
end

print('[gf_testbridge] prêt (développement)')

-- La commande ne vient que de la console serveur, jamais d'un joueur.
RegisterCommand('gf_bridge', function(source, args)
    if source ~= 0 then
        print('[gf_testbridge] refus : commande réservée à la console serveur')
        return
    end
    local action = args[1]
    if action ~= 'open' and action ~= 'close' and action ~= 'status' and action ~= 'whoami' then
        print('[gf_testbridge] usage : gf_bridge <open|close|status> <page> | gf_bridge whoami')
        return
    end
    local joueurs = GetPlayers()
    if #joueurs ~= 1 then
        print('[gf_testbridge] aucun joueur unique connecté')
        return
    end
    if action == 'whoami' then
        -- Aide au poste de développement : identifiants du joueur unique, pour
        -- poser un principal admin local sans toucher au code du jeu.
        local prefixes = { 'license:', 'license2:', 'fivem:', 'discord:', 'steam:', 'xbl:', 'live:' }
        local trouves = {}
        for _, identifiant in ipairs(GetPlayerIdentifiers(tonumber(joueurs[1])) or {}) do
            for _, prefixe in ipairs(prefixes) do
                if identifiant:sub(1, #prefixe) == prefixe then
                    trouves[#trouves + 1] = identifiant
                    break
                end
            end
        end
        if #trouves == 0 then
            print('[gf_testbridge] identifiants : aucun')
        else
            print(('[gf_testbridge] identifiants : %s'):format(table.concat(trouves, ', ')))
        end
        return
    end
    local page = args[2]
    if not GfTestbridge.estPage(page) then
        print(('[gf_testbridge] page inconnue. Pages valides : %s')
            :format(table.concat(GfTestbridge.PAGES, ', ')))
        return
    end
    TriggerClientEvent('gf_testbridge:demande', tonumber(joueurs[1]), {
        page = page,
        action = action,
    })
end, true)

RegisterNetEvent('gf_testbridge:clientPret', function()
    print(('[gf_testbridge] client prêt id=%d'):format(source))
end)

RegisterNetEvent('gf_testbridge:rapport', function(rapport)
    local ligne = GfTestbridge.ligne(rapport)
    if ligne then print(ligne) end
end)
