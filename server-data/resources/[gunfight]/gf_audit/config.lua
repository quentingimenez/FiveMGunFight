-- Ces seuils sont des valeurs de départ choisies, non mesurées. Aucune sanction
-- n'est appliquée tant que le taux de fausses alertes n'a pas été mesuré
-- (chantier C3) : ils ne changent aucune règle de jeu.

Config = Config or {}

Config.Audit = {
    enabled = true,
    intervalleMs = 1000,
    fenetreMortMs = 3000,
    graceMs = 3000,
    tolerance = 2,
    modes = { attack = true, redzone = true },
}
