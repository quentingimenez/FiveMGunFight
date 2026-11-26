Config = {}

-- Véhicules disponibles sur le serveur (onglet « Véhicule » de /customveh).
-- Pour en ajouter un : py scripts/ajouter_vehicule.py <pack> --nom "Nom" (voir
-- docs/ajouter-un-modele.md) : il copie les fichiers, les déclare et ajoute la ligne ici.
-- Photo du menu : /thumbs vehicles <modèle> en jeu (gf_thumbs) ; sans photo, une silhouette.
Config.Vehicles = {
    { model = 'gstbisxl3', label = 'Bison XL Hellfire' },
    { model = 'keyhawk',   label = 'Jeep Trackhawk' },
    { model = 'gbbisonhf', label = 'Bison HF' },
    { model = 'astronmans', label = 'Astron Mansory' },
}

-- Véhicule de base tant qu'aucun admin n'en a choisi un autre
Config.DefaultModel = 'gstbisxl3'

-- Fichier où le véhicule de base et les customs sont enregistrés (dans la ressource)
-- Format : { base = modèle, customs = { [modèle] = { ...propriétés... } } }.
-- Plus tard : un véhicule et une custom par joueur et par mode.
Config.CustomFile = 'custom/custom.json'

-- Pièces proposées dans le menu (types de mods GTA). Seules celles que le modèle
-- possède réellement s'affichent. Pas de pièces de performance (moteur, freins...)
-- pour garder les véhicules égaux.
Config.ModSlots = {
    { type = 0,  label = 'Aileron' },
    { type = 1,  label = 'Pare-chocs avant' },
    { type = 2,  label = 'Pare-chocs arrière' },
    { type = 3,  label = 'Bas de caisse' },
    { type = 4,  label = 'Échappement' },
    { type = 5,  label = 'Arceau' },
    { type = 6,  label = 'Calandre' },
    { type = 7,  label = 'Capot' },
    { type = 8,  label = 'Aile gauche' },
    { type = 9,  label = 'Aile droite' },
    { type = 10, label = 'Toit' },
    { type = 25, label = 'Support de plaque' },
    { type = 48, label = 'Motif (livrée)' },
}

Config.PaintTypes = { 'Normal', 'Métallisé', 'Nacré', 'Mat', 'Métal', 'Chrome' }

Config.WheelTypes = { 'Sport', 'Muscle', 'Lowrider', 'SUV', 'Tout-terrain', 'Tuner', 'Moto', 'Haut de gamme' }

Config.WindowTints = { 'Aucune', 'Noir intégral', 'Fumé foncé', 'Fumé clair', 'Origine', 'Limousine', 'Vert' }

Config.PlateStyles = { 'Bleu sur blanc 1', 'Jaune sur noir', 'Jaune sur bleu', 'Bleu sur blanc 2', 'Bleu sur blanc 3', 'Yankton' }

Config.XenonColors = { 'Blanc', 'Bleu', 'Bleu électrique', 'Vert menthe', 'Vert citron', 'Jaune', 'Doré',
    'Orange', 'Rouge', 'Rose poney', 'Rose vif', 'Violet', 'Lumière noire' }

-- Couleurs GTA (index) pour le nacré et les jantes
Config.GameColors = {
    { id = 0,   label = 'Noir' },
    { id = 4,   label = 'Argent' },
    { id = 111, label = 'Blanc' },
    { id = 27,  label = 'Rouge' },
    { id = 38,  label = 'Orange' },
    { id = 89,  label = 'Jaune' },
    { id = 92,  label = 'Vert citron' },
    { id = 53,  label = 'Vert' },
    { id = 64,  label = 'Bleu' },
    { id = 70,  label = 'Bleu vif' },
    { id = 145, label = 'Violet' },
    { id = 135, label = 'Rose' },
    { id = 158, label = 'Or' },
    { id = 120, label = 'Chrome' },
}

Config.PlateMaxLength = 8
