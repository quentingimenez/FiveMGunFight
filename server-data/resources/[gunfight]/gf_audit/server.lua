-- Audit passif : aucun envoi au client, aucune sanction, aucune modification
-- de l'état des joueurs. Les événements écoutés ici sont locaux au serveur.

local etat = AuditVie.nouveau()
local regles = {
    fenetreMortMs = Config.Audit.fenetreMortMs,
    graceMs = Config.Audit.graceMs,
    tolerance = Config.Audit.tolerance,
}

AddEventHandler('gf:spawned', function(src)
    AuditVie.apparition(etat, src, GetGameTimer(), regles)
end)

AddEventHandler('gf:armourGranted', function(src)
    AuditVie.soinAccorde(etat, src, GetGameTimer(), regles)
end)

AddEventHandler('gf:healGranted', function(src)
    AuditVie.soinAccorde(etat, src, GetGameTimer(), regles)
end)

AddEventHandler('gf:itemUsed', function(src, stat, quantite, dureeMs)
    AuditVie.objetUtilise(etat, src, stat, quantite, dureeMs, GetGameTimer(), regles)
end)

AddEventHandler('gf:hit', function(data)
    if type(data) ~= 'table' or type(data.victim) ~= 'number' then return end
    AuditVie.touche(etat, data.victim, data.willKill, data.accepted, GetGameTimer())
end)

AddEventHandler('gf:playerKilled', function(victim)
    if type(victim) == 'number' then AuditVie.mort(etat, victim) end
end)

AddEventHandler('gf:modeLeft', function(src)
    AuditVie.oublier(etat, src)
end)

AddEventHandler('playerDropped', function()
    AuditVie.oublier(etat, source)
end)

CreateThread(function()
    while true do
        Wait(Config.Audit.intervalleMs)
        if Config.Audit.enabled then
            for _, identifiant in ipairs(GetPlayers()) do
                local src = tonumber(identifiant)
                if src then
                    local okMode, mode = pcall(function()
                        return exports.gf_core:GetMode(src)
                    end)
                    if okMode and Config.Audit.modes[mode] then
                        local ped = GetPlayerPed(src)
                        if ped and ped ~= 0 then
                            local okMesure, vie, armure = pcall(function()
                                return GetEntityHealth(ped), GetPedArmour(ped)
                            end)
                            if okMesure then
                                local mort = Validation.mortConfirmee(src, {
                                    ped = GetPlayerPed,
                                    health = GetEntityHealth,
                                    dead = function(p)
                                        local okDead, dead = pcall(IsEntityDead, p)
                                        return okDead and dead == true
                                    end,
                                })
                                local anomalies = AuditVie.mesure(
                                    etat, src, vie, armure, mort, GetGameTimer(), regles
                                )
                                for _, anomalie in ipairs(anomalies) do
                                    anomalie.src = src
                                    TriggerEvent('gf:anomalie', anomalie)
                                    print(('[gf_audit] anomalie %s joueur %d'):format(
                                        tostring(anomalie.type), src
                                    ))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)
