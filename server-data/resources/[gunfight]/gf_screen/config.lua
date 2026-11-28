-- =============================================================================
--  gf_screen - CONFIGURATION (shared_script, Lua 5.4)
--  Valeurs lues aussi bien par le serveur (durée, limite de réception) que par
--  le client (paramètres de capture). Aucune autre globale que Config ici.
-- =============================================================================

Config = {}

-- Images par seconde demandées à la cible. Borné à 1..5 pour éviter une capture
-- qui saturerait le réseau du joueur regardé.
Config.Fps = math.max(1, math.min(5, 3))

-- Largeur en pixels des images (la hauteur est déduite côté client) : 640 garde
-- une image lisible sans dépasser le budget réseau d'un envoi latent.
Config.Width = 640

-- Qualité JPEG (0..1). 0.5 réduit fortement la taille des images transmises.
Config.Quality = 0.5

-- Longueur maximale d'une image encodée en base64 acceptée par le serveur
-- (préfixe compris). Au-delà, l'image est rejetée avant tout relais.
Config.MaxFrameChars = 250000

-- Durée maximale d'un visionnage, en secondes (10 minutes).
Config.MaxSeconds = 600
