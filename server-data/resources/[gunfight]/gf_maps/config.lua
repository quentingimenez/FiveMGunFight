-- =============================================================================
--  gf_maps - configuration de l'éditeur de maps (/editor)
-- =============================================================================

Config = Config or {}

-- Caméra de l'éditeur : elle tourne autour du point visé au sol.
-- Les angles suivent la convention de GTA (SetCamRot, ordre 2) : pitch négatif
-- vers le bas, yaw (cap) croissant dans le sens inverse des aiguilles d'une
-- montre, 0 = nord. Ces valeurs sont des choix de confort, pas des mesures.
Config.EditorCamera = {
    -- Vue du dessus, en degrés. -89.9 et non -90 : à -90 pile, le cap de la
    -- caméra n'est plus défini (valeur reprise de l'ancienne caméra fixe).
    pitchTopDeg = -89.9,
    -- Inclinaison maximale, en degrés : au-delà, l'horizon entre dans l'image
    -- et les clics lointains tombent hors de la zone utile.
    pitchMinDeg = -25.0,
    -- Molette maintenue + glisser : degrés par pixel de souris.
    dragDegPerPx = 0.3,
    -- Boutons du panneau : pas de rotation et d'inclinaison, en degrés.
    stepYawDeg = 45.0,
    stepPitchDeg = 15.0,
    -- Hauteur minimale de la caméra au-dessus du sol sous elle, en mètres
    -- (vue inclinée près d'une colline ou d'un immeuble).
    groundClearanceM = 5.0,
}
