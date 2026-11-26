Config = {}

Config.ServerName = 'GUNFIGHT'
Config.DefaultMode = 'attack'
Config.BucketBase = 1000
Config.RequestCooldownMs = 500 -- cadence minimale des lectures NUI (state, joueurs)
Config.CharacterStorage = 'data/characters.json'
Config.PedModels = {
  male = 'mp_m_freemode_01',
  female = 'mp_f_freemode_01',
}

Config.Party = {
  maxSize = 4,
  inviteTimeout = 30, -- secondes
  inviteCooldown = 2, -- secondes entre deux invitations
  modeCooldown = 1,   -- secondes entre deux changements de mode
}

Config.Character = {
  nameMin = 3,
  nameMax = 20,
  skins = 5,
  -- Apparence avancée : plafonds appliqués côté client et côté serveur.
  maxTattoos = 24,
  maxTattoosPerZone = 4,
}

-- Recherche serveur globale pour les modes 20-30 joueurs.
-- Un joueur seul peut lancer la recherche : la taille de l'escouade n'est pas
-- un critère. Tous les joueurs du lobby avec un personnage sont inscrits.
Config.Matchmaking = {
  attackMin = 20, -- seuil de lancement (montée jusqu'à 2 équipes de 15)
  attackMax = 30, -- plafond d'inscription, configuration documentaire
}

-- Scène du lobby et de la création : les personnages sont alignés face à la
-- caméra, dans le vide (rien de la map entre la caméra et l'image de fond).
-- `z` est l'altitude de la racine du ped. La hauteur du regard n'est pas
-- réglable : elle est calculée pour poser les pieds sur la ligne de sol de
-- l'image de fond (client.lua).
Config.Stage = {
  x = 0.0,
  y = 0.0,
  z = 1000.0,
  heading = 0.0,
  spacing = 1.45,
  camera = {
    baseDistance = 4.4,
    distancePerMember = 0.95,
    height = 1.52,
    fov = 42.0,
    -- Plan de création : corps entier, centré sur la colonne de scène.
    creatorDistance = 4.2,
    creatorOffset = 0.0,
    creatorFov = 40.0,
    creatorHeight = 1.45,
    creatorLookOffset = 0.0,
  },
}

-- Catalogue NUI. `resource` permet de verifier la disponibilite cote serveur.
Config.Modes = {
  {
    id = 'attack',
    label = 'Attaque de zone',
    short = 'ATTAQUE',
    description = 'Deux equipes, la derniere en vie remporte la manche.',
    icon = 'target',
    resource = 'gf_attack',
    minPlayers = 1, -- recherche serveur : pas de condition sur l'escouade
    placeholder = false,
  },
  {
    id = 'redzone',
    label = 'Redzone',
    short = 'REDZONE',
    description = 'Chacun pour soi dans une zone qui se referme.',
    icon = 'zone',
    resource = 'gf_redzone',
    minPlayers = 1,
    placeholder = false,
  },
  {
    id = 'gungame',
    label = 'Gun Game',
    short = 'GUN GAME',
    description = 'Chaque elimination fait passer a l arme suivante.',
    icon = 'weapon',
    resource = nil,
    placeholder = true,
  },
  {
    id = 'tdm',
    label = 'Team Deathmatch',
    short = 'TDM',
    description = 'Affrontement en equipes sur une map dediee.',
    icon = 'team',
    resource = nil,
    placeholder = true,
  },
}
