-- =============================================================================
--  gf_screen - CONFIGURATION (shared_script, Lua 5.4)
--  Valeurs lues aussi bien par le serveur (durée, limite de réception) que par
--  le client (paramètres de capture). Aucune autre globale que Config ici.
-- =============================================================================

Config = {}

-- Préréglages de capture : width = largeur en pixels (la hauteur est déduite
-- côté client), fps = images par seconde, quality = qualité de compression (0..1).
-- Attention : ultra coûte environ 1 Mo/s d'envoi au joueur regardé. Au-delà de
-- 15 i/s en 1280 px, l'encodage dans la page dépasse le temps d'une image et le
-- jeu du joueur ralentit.
Config.Presets = {
    basse   = { width = 640,  fps = 3, quality = 0.5 },
    moyenne = { width = 960,  fps = 5, quality = 0.6 },
    haute   = { width = 1280, fps = 8, quality = 0.7 },
    ultra   = { width = 1280, fps = 15, quality = 0.6 },
}

-- Préréglage utilisé quand la commande screen ne précise pas de qualité.
Config.DefaultPreset = 'haute'

-- Longueur maximale d'une image encodée en base64 acceptée par le serveur
-- (préfixe compris). Au-delà, l'image est rejetée avant tout relais.
Config.MaxFrameChars = 600000

-- Budgets réseau, en octets par seconde : montée (cible → serveur) et
-- relais latent (serveur → administrateur).
Config.UploadBps = 1000000
Config.ForwardBps = 1500000

-- Durée maximale d'un visionnage, en secondes (10 minutes).
Config.MaxSeconds = 600
