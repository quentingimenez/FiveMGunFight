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
}

-- Scene du lobby : les personnages sont alignes face a la camera.
Config.Stage = {
  x = -1037.7,
  y = -2737.9,
  z = 20.2,
  heading = 330.0,
  spacing = 1.45,
  camera = {
    baseDistance = 3.2,
    distancePerMember = 0.95,
    height = 1.52,
    lookHeight = 1.12,
    fov = 42.0,
    creatorDistance = 2.9,
    creatorOffset = -0.75,
    creatorFov = 34.0,
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
    minPlayers = 2,
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
