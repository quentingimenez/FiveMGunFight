-- =============================================================================
--  gf_killcam - CONFIGURATION partagée (client et serveur)
--  Toutes les durées sont en millisecondes sauf BufferSeconds et
--  ReplaySeconds, exprimés en secondes. OthersRadius est en mètres.
-- =============================================================================

Config = {}

-- Activer ou désactiver complètement l'enregistrement et la lecture de la killcam.
Config.Enabled = true

-- Durée du tampon serveur conservé pour chaque joueur (en secondes).
-- Doit couvrir au moins ReplaySeconds.
Config.BufferSeconds = 30

-- Durée du clip rejoué à la victime après sa mort (en secondes).
Config.ReplaySeconds = 8

-- Intervalle entre deux échantillons enregistrés par le client (en millisecondes).
Config.SampleMs = 100

-- Intervalle entre deux envois au serveur (en millisecondes).
-- Un lot contient au plus 15 échantillons, soit 1500 ms à 100 ms par échantillon ;
-- avec 1000 ms par défaut, chaque lot tient dans la limite du contrat.
Config.BatchMs = 1000

-- Nombre maximum de joueurs proches inclus dans le clip en plus du tueur et de la victime.
Config.MaxOthers = 6

-- Distance maximale (en mètres) entre le tueur et un autre joueur pour l'inclure
-- dans `others`.
Config.OthersRadius = 120.0

-- Modes de jeu dans lesquels l'enregistrement est actif.
-- La clé doit correspondre à LocalPlayer.state.gf_mode côté client.
Config.Modes = {
    attack = true,   -- Attaque : mode principal de prise de zone
    redzone = true,  -- Redzone : chacun pour soi autour d'une zone fixe
}
