Config = {}

-- =============================================================================
--  gf_thumbs : photos (miniatures) générées en jeu à partir des modèles 3D.
--
--  Une « famille » (kind) = un type d'objet photographié. Chaque famille dit :
--   - provider : d'où vient la liste des identifiants (export client d'une autre
--                ressource, qui renvoie { { id = ..., label = ... }, ... }) ;
--   - subject  : comment poser l'objet devant la caméra (vehicle, weapon, ...) ;
--   - width / height : taille de l'image finale (fond transparent, objet centré) ;
--   - auto     : true = les photos manquantes sont prises toutes seules quand un
--                admin arrive au lobby (rien à faire après l'ajout d'un modèle).
--  Ajouter une famille (ex. tenues) = une entrée ici + un « subject » dans client.lua.
-- =============================================================================
Config.Kinds = {
    vehicles = {
        provider = { resource = 'gf_vehicles', export = 'GetThumbList' },
        subject = 'vehicle',
        width = 512, height = 288,
        auto = true,
    },
    weapons = {
        provider = { resource = 'gf_core', export = 'GetWeaponThumbList' },
        subject = 'weapon',
        width = 512, height = 256,
        auto = true,
    },
}

-- Photos manquantes prises automatiquement à l'arrivée d'un admin au lobby
Config.AutoCapture = true
-- Attente après l'arrivée au lobby (ms), le temps que tout soit chargé
Config.AutoCaptureDelay = 8000

-- Studio : point isolé au-dessus de l'océan, loin de tout décor
Config.Studio = { x = -1800.0, y = -4200.0, z = 700.0 }

-- Fond vert (détouré ensuite en transparent dans la page NUI)
Config.KeyColor = { r = 0, g = 255, b = 0 }

-- Champ de la caméra (petit = peu de déformation)
Config.Fov = 30.0

-- Taille maximale d'une image reçue (octets du PNG décodé)
Config.MaxImageBytes = 1024 * 1024

-- Dossier de stockage dans la ressource : thumbs/<famille>/<id>.png
-- (en production : volume « thumbs », complété depuis l'image au démarrage)
Config.Folder = 'thumbs'
