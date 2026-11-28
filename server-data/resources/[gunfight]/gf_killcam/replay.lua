-- Lecture de la killcam : rejoue le point de vue du tueur a partir du clip recu.
-- Ce fichier ne fait aucun appel reseau sortant et ne touche pas a gf_core:spawned.

local etat = nil
local generation = 0

local MODELE_FREEMODE = joaat('mp_m_freemode_01') -- calcule une fois au chargement.

-- Affiche un texte centre avec le modele utilise par gf_admin.
local function afficherTexte(texte, x, y)
    SetTextFont(4)
    SetTextScale(0.35, 0.35)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(texte)
    EndTextCommandDisplayText(x, y)
end

-- Tronque un nom pour l'affichage (32 caracteres maximum).
local function nomAffiche(nom)
    if type(nom) ~= 'string' or nom == '' then
        return '?'
    end
    return string.sub(nom, 1, 32)
end

-- Termine la killcam en cours. Idempotent : le premier appel vide l'etat,
-- les suivants ne font rien. Aucun Wait ici pour onResourceStop.
local function terminer()
    local courant = etat
    if courant == nil then
        return
    end
    etat = nil
    generation = generation + 1

    DoScreenFadeOut(200)

    for _, clone in ipairs(courant.clones) do
        if DoesEntityExist(clone.ped) then
            SetEntityAsMissionEntity(clone.ped, true, true)
            DeleteEntity(clone.ped)
        end
    end

    if courant.cam ~= nil then
        RenderScriptCams(false, false, 0, true, true)
        if DoesCamExist(courant.cam) then
            DestroyCam(courant.cam, false)
        end
    end

    if courant.modeleDemande then
        SetModelAsNoLongerNeeded(MODELE_FREEMODE)
    end

    DoScreenFadeIn(200)
end

-- Cree un ped local a partir de l'echantillon initial, par clonage si le joueur
-- est present localement, sinon depuis mp_m_freemode_01.
local function creerClone(acteur, estTueur, arme, session, courant)
    local echantillon = GFKillcamTrack.sample(acteur.samples, 0)
    if echantillon == nil then
        echantillon = acteur.samples[1]
    end
    if echantillon == nil then
        return nil
    end

    local clone = 0
    local distant = false
    local joueur = GetPlayerFromServerId(acteur.id)
    if joueur ~= -1 then
        local ped = GetPlayerPed(joueur)
        if ped ~= 0 and DoesEntityExist(ped) then
            -- Clone local : pas de reseau, pas d'hote de script, blend copie.
            clone = ClonePed(ped, false, false, true)
        end
    end

    if clone == 0 or not DoesEntityExist(clone) then
        if not HasModelLoaded(MODELE_FREEMODE) then
            -- Le drapeau est pose des l'appel : meme en cas d'echec ou de
            -- remplacement de session, terminer() saura liberer le modele.
            RequestModel(MODELE_FREEMODE)
            courant.modeleDemande = true
            local echeance = GetGameTimer() + 3000
            while not HasModelLoaded(MODELE_FREEMODE) do
                Wait(10)
                if etat == nil or courant.session ~= session then
                    -- L'etat a deja ete termine par la killcam qui l'a remplace :
                    -- terminer() a libere le modele demande, ne pas le liberer
                    -- une seconde fois.
                    return nil
                end
                if GetGameTimer() >= echeance then
                    return nil
                end
            end
        end
        clone = CreatePed(4, MODELE_FREEMODE, echantillon.x, echantillon.y,
            echantillon.z - 1.0, echantillon.h, false, false)
        distant = true
    end

    if clone == 0 or not DoesEntityExist(clone) then
        return nil
    end

    -- Place le clone des la creation : le fondu entrant dure 200 ms et la
    -- boucle de lecture ne tourne pas encore. La racine du ped est ~1 m
    -- au-dessus du sol, d'ou le decalage sur z.
    SetEntityCoordsNoOffset(clone, echantillon.x, echantillon.y,
        echantillon.z - 1.0, false, false, false)
    SetEntityHeading(clone, echantillon.h)

    SetEntityInvincible(clone, true)
    SetEntityCollision(clone, false, true)
    SetBlockingOfNonTemporaryEvents(clone, true)
    FreezeEntityPosition(clone, true)

    -- ClonePed copie l'equipement : on retire les armes heritees.
    RemoveAllPedWeapons(clone, true)
    if estTueur and type(arme) == 'number' and arme > 0 then
        GiveWeaponToPed(clone, arme, 0, false, true)
        SetCurrentPedWeapon(clone, arme, true)
    end

    return { ped = clone, samples = acteur.samples, cree = distant,
        viser = false, cibleX = 0.0, cibleY = 0.0, cibleZ = 0.0 }
end

-- Point situe 50 m devant la camera de l'echantillon (zone de visee).
local function calculerCible(echantillon)
    local rx = math.rad(echantillon.rx or 0.0)
    local rz = math.rad(echantillon.rz or 0.0)
    local cosRx = math.cos(rx)
    local dirX = -math.sin(rz) * cosRx
    local dirY = math.cos(rz) * cosRx
    local dirZ = math.sin(rx)
    return echantillon.cx + dirX * 50.0,
        echantillon.cy + dirY * 50.0,
        echantillon.cz + dirZ * 50.0
end

-- Valide un clip sans jamais toucher a la killcam en cours.
local function clipValide(clip)
    if type(clip) ~= 'table' then
        return false
    end
    if type(clip.duration) ~= 'number' or clip.duration ~= clip.duration
        or clip.duration < 1 or clip.duration > 30 then
        return false
    end
    if type(clip.killer) ~= 'table' or type(clip.killer.samples) ~= 'table'
        or #clip.killer.samples == 0 then
        return false
    end
    return true
end

RegisterNetEvent('gf_killcam:play', function(clip)
    if Config.Enabled == false or not clipValide(clip) then
        return
    end

    -- Une seule killcam : l'ancienne est fermee par le chemin unique.
    terminer()

    local session = generation + 1
    local courant = {
        session = session,
        clip = clip,
        clones = {},
        cam = nil,
        debut = 0,
        modeleDemande = false,
        nomTueur = nomAffiche(clip.killer.name)
    }
    etat = courant

    DoScreenFadeOut(200)
    Wait(200)
    if etat ~= courant or courant.session ~= session then
        return
    end

    -- Acteur principal : le tueur, puis la victime et les autres.
    local acteurs = {
        { acteur = clip.killer, estTueur = true },
        { acteur = clip.victim, estTueur = false }
    }
    if type(clip.others) == 'table' then
        for _, autre in ipairs(clip.others) do
            table.insert(acteurs, { acteur = autre, estTueur = false })
        end
    end

    for _, entree in ipairs(acteurs) do
        local acteur = entree.acteur
        if type(acteur) == 'table' and type(acteur.samples) == 'table'
            and #acteur.samples > 0 then
            local clone = creerClone(acteur, entree.estTueur, clip.weapon,
                session, courant)
            if clone == nil then
                -- Si la session a ete remplacee pendant l'attente du modele,
                -- ne surtout pas fermer la NOUVELLE killcam.
                if etat ~= courant or courant.session ~= session then
                    return
                end
                terminer()
                return
            end
            table.insert(courant.clones, clone)
        end
        if etat ~= courant or courant.session ~= session then
            return
        end
    end

    -- La camera est deja au point de vue du tueur avant le fondu entrant.
    local initial = GFKillcamTrack.sample(clip.killer.samples, 0)
    if initial == nil then
        initial = clip.killer.samples[1]
    end
    if initial == nil then
        terminer()
        return
    end

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if cam == nil or cam == 0 or not DoesCamExist(cam) then
        terminer()
        return
    end
    courant.cam = cam
    SetCamCoord(cam, initial.cx, initial.cy, initial.cz)
    SetCamRot(cam, initial.rx, initial.ry, initial.rz, 2)
    RenderScriptCams(true, false, 0, true, true)
    DoScreenFadeIn(200)

    -- t=0 correspond au debut reel de la lecture, apres le fondu entrant.
    courant.debut = GetGameTimer()

    CreateThread(function()
        while etat == courant and courant.session == session do
            Wait(0)
            if etat ~= courant or courant.session ~= session then
                return
            end

            local t = GetGameTimer() - courant.debut
            if t >= clip.duration * 1000 or IsControlJustPressed(0, 22) then
                terminer()
                return
            end

            local tueur = courant.clones[1]
            for _, clone in ipairs(courant.clones) do
                local s = GFKillcamTrack.sample(clone.samples, t)
                if s ~= nil then
                    SetEntityCoordsNoOffset(clone.ped, s.x, s.y, s.z - 1.0,
                        false, false, false)
                    SetEntityHeading(clone.ped, s.h)

                    if clone == tueur then
                        -- Point de vue exact du tueur, sans offset ni lissage.
                        SetCamCoord(courant.cam, s.cx, s.cy, s.cz)
                        SetCamRot(courant.cam, s.rx, s.ry, s.rz, 2)
                    end

                    local vise = s.a == true
                    if vise then
                        -- keepTasks=false supprime la tache a chaque teleport :
                        -- reemettre la visee chaque frame, cible recalculee.
                        local cibleX, cibleY, cibleZ = calculerCible(s)
                        TaskAimGunAtCoord(clone.ped, cibleX, cibleY, cibleZ,
                            60000, true, false)
                    elseif clone.viser then
                        ClearPedTasks(clone.ped)
                    end
                    clone.viser = vise
                elseif clone.viser then
                    ClearPedTasks(clone.ped)
                    clone.viser = false
                end
            end

            afficherTexte(('KILLCAM — tué par %s'):format(courant.nomTueur),
                0.5, 0.04)
            afficherTexte('ESPACE : passer', 0.5, 0.95)
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        terminer()
    end
end)
