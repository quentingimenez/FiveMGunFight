-- Configuration luacheck du dépôt FiveMGunFight.
--
-- Le code Lua est exécuté par FiveM (Lua 5.4 côté serveur) et s'appuie sur des
-- centaines de fonctions natives et de globales fournies par le runtime, que
-- luacheck ne connaît pas. La liste exhaustive de ces natives est un travail
-- ultérieur : en attendant, l'accès à une globale non définie (W113) est
-- ignoré pour éviter des centaines de faux positifs. Les affectations de
-- globales inconnues (W111/W112) restent contrôlées : une faute de frappe sur
-- une globale est donc toujours signalée.

std = "lua54"

ignore = {
  -- W113 : accès à une globale non définie (natives FiveM, cf. en-tête).
  "113",
  -- W212 : argument de callback non utilisé. Les événements FiveM imposent
  -- souvent une signature complète ; garder le paramètre documente l'API.
  "212",
}

-- Table de configuration partagée, déclarée puis complétée par les fichiers
-- config.lua des ressources gunfight.
globals = {
  "Config",
  -- Modules chargés par fxmanifest.lua et exposés volontairement en globales
  -- (pas de `return` : FiveM les partage entre fichiers de la ressource).
  "AttackRules",
  "AuditVie",
  "Base64",
  "GFAdminCommands",
  -- Module partagé de suivi des échantillons de la killcam (gf_killcam).
  "GFKillcamTrack",
  "GFLobbyAppearance",
  "GFLobbyAppearanceSchema",
  "GFLobbyBackdrop",
  "GFMapsCamera",
  "GFMenuState",
  -- Modules partagés de la passerelle de test NUI (gf_testbridge).
  "GfTestbridge",
  "GfTestbridgeGuard",
  "GardeEtat",
  -- Globale fournie par le runtime FiveM (W112 sur les champs mutés).
  "GlobalState",
  "Journal",
  "MigrationPlan",
  "Migrations",
  "MySQL",
  "RateLimit",
  "Validation",
  "WeaponAccessories",
  "ShotValidation",
}

-- Le code vendorisé de [cfx-default] provient des ressources Cfx par défaut.
-- Il n'est pas maintenu ici et n'a pas à être corrigé par ce dépôt : on
-- l'exclut de l'analyse plutôt que d'ignorer globalement ses avertissements.
exclude_files = {
  "server-data/resources/**/baseevents/**",
  "server-data/resources/**/mapmanager/**",
  "server-data/resources/**/spawnmanager/**",
  -- Ressource tierce vendorisée, comme [cfx-default] : non maintenue ici.
  "server-data/resources/**/oxmysql/**",
}

-- Les lignes longues restantes sont héritées du code gunfight existant. La
-- limite est fixée à 200 colonnes pour laisser passer l'existant tout en
-- signalant les nouvelles lignes déraisonnables.
max_line_length = 200
