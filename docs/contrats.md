# Contrats entre ressources

Ce document est généré par `python scripts/contrats.py --doc` : il ne se modifie pas à la main.

## gf_admin

- Exports fournis
  - LogAction
- Exports consommés
  - gf_db:Pret
  - gf_thumbs:Get
- Événements émis
  - gf:healGranted
  - gf_lobby:menuOverlay
  - gf_ui:announce
  - gf_ui:notify
- Événements écoutés
  - gf_core:modeChanged
  - gf_core:spawned
  - gf_lobby:state
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_core
  - gf_db
  - oxmysql
- Dépendances optionnelles
  - gf_db
  - gf_thumbs
- Dette
  - cycle:gf_core

## gf_attack

- Exports fournis
  - CanJoin
  - GetMapChoices
  - RegisterSquads
  - SetNextMap
  - StartTestRound
- Exports consommés
  - gf_admin:LogAction
  - gf_lobby:ForceLaunchQueue
  - gf_maps:GetActiveMaps
- Événements émis
  - gf:itemUsed
  - gf:matchAborted
  - gf:matchEnded
  - gf:matchResults
  - gf:matchStarted
  - gf:modeKill
  - gf:phase
  - gf:roundEnded
  - gf_ui:announce
  - gf_ui:hud
  - gf_ui:items
  - gf_ui:loadout_close
  - gf_ui:loadout_open
  - gf_ui:match_results
  - gf_ui:scoreboard
- Événements écoutés
  - gf:loadoutChosen
  - gf:modeJoined
  - gf:modeLeft
  - gf:playerKilled
  - gf_core:modeChanged
  - gf_core:spawned
  - gf_maps:updated
- State bags écrits
  - gf_alive
- State bags lus
  - gf_alive
  - gf_mode
  - gf_protected
  - gf_team
- Dépendances dures
  - gf_core
  - gf_maps
  - gf_ui
- Dépendances optionnelles
  - gf_admin
  - gf_lobby
- Dette
  - cycle:gf_core
  - cycle:gf_lobby

## gf_audit

- Exports fournis
  - Aucun.
- Exports consommés
  - gf_core:GetMode
- Événements émis
  - gf:anomalie
- Événements écoutés
  - gf:armourGranted
  - gf:healGranted
  - gf:hit
  - gf:itemUsed
  - gf:modeLeft
  - gf:playerKilled
  - gf:spawned
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_core
- Dépendances optionnelles
  - Aucun.
- Dette
  - Aucun.

## gf_core

- Exports fournis
  - BuildWeaponList
  - DeleteModeVehicle
  - DeleteVehicle
  - Freeze
  - GetEquippedWeapons
  - GetMode
  - GetModeVehicle
  - GetOwnedWeapons
  - GetPlayersInMode
  - GetSelectionSettings
  - GetStarterWeapons
  - GetTeam
  - GetWeaponCatalog
  - GetWeaponThumbList
  - GiveModeVehicle
  - GiveWeapons
  - IsAdmin
  - IsProtected
  - Notify
  - OwnsWeapon
  - ResolveSelection
  - SetMode
  - SetProtected
  - SetTeam
  - Spawn
  - UpdateRedzoneWeapons
- Exports consommés
  - gf_admin:LogAction
  - gf_attack:CanJoin
  - gf_vehicles:ApplyCustom
- Événements émis
  - gf:anomalie
  - gf:armourGranted
  - gf:hit
  - gf:modeJoined
  - gf:modeLeft
  - gf:playerKilled
  - gf:spawned
  - gf_ui:hit
  - gf_ui:hud
  - gf_ui:kill
  - gf_ui:killfeed
  - gf_ui:notify
  - gf_ui:scoreboard
  - gf_ui:weapons
- Événements écoutés
  - Aucun.
- State bags écrits
  - gf_mode
  - gf_protected
  - gf_team
- State bags lus
  - gf_mode
  - gf_vehicle_base
  - gf_vehicle_versions
- Dépendances dures
  - gf_ui
- Dépendances optionnelles
  - gf_admin
  - gf_attack
  - gf_inventory
  - gf_vehicles
- Dette
  - cycle:gf_admin
  - cycle:gf_attack

## gf_db

- Exports fournis
  - Pret
  - Version
- Exports consommés
  - Aucun.
- Événements émis
  - Aucun.
- Événements écoutés
  - Aucun.
- State bags écrits
  - gf_db_version
- State bags lus
  - Aucun.
- Dépendances dures
  - oxmysql
- Dépendances optionnelles
  - Aucun.
- Dette
  - Aucun.

## gf_inventory

- Exports fournis
  - GetEquipped
  - GetObtained
  - GetWeaponAccessories
  - GiveWeaponToLocker
- Exports consommés
  - gf_admin:LogAction
  - gf_db:Pret
  - gf_redzone:CanChangeWeapons
- Événements émis
  - Aucun.
- Événements écoutés
  - Aucun.
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_core
  - gf_db
  - gf_weapons
  - oxmysql
- Dépendances optionnelles
  - gf_admin
  - gf_db
  - gf_redzone
- Dette
  - Aucun.

## gf_journal

- Exports fournis
  - Aucun.
- Exports consommés
  - gf_core:GetMode
  - gf_core:GetTeam
  - gf_db:Pret
- Événements émis
  - Aucun.
- Événements écoutés
  - gf:anomalie
  - gf:hit
  - gf:matchAborted
  - gf:matchEnded
  - gf:matchResults
  - gf:matchStarted
  - gf:modeJoined
  - gf:modeKill
  - gf:modeLeft
  - gf:phase
  - gf:playerKilled
  - gf:roundEnded
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_db
  - oxmysql
- Dépendances optionnelles
  - Aucun.
- Dette
  - dependance-cachee:gf_core

## gf_killcam

- Exports fournis
  - RemainingMs
- Exports consommés
  - gf_core:GetMode
- Événements émis
  - Aucun.
- Événements écoutés
  - gf:modeLeft
  - gf:playerKilled
- State bags écrits
  - Aucun.
- State bags lus
  - gf_mode
- Dépendances dures
  - gf_core
- Dépendances optionnelles
  - Aucun.
- Dette
  - Aucun.

## gf_lobby

- Exports fournis
  - ForceLaunchQueue
  - GetLobbyAppearance
- Exports consommés
  - gf_admin:LogAction
  - gf_attack:CanJoin
  - gf_attack:GetMapChoices
  - gf_attack:RegisterSquads
  - gf_attack:SetNextMap
  - gf_core:GetMode
  - gf_core:GetPlayersInMode
  - gf_core:SetMode
- Événements émis
  - gf_ui:hud
  - gf_ui:notify
- Événements écoutés
  - gf:modeJoined
  - gf:modeLeft
  - gf_core:modeChanged
  - gf_core:spawned
- State bags écrits
  - Aucun.
- State bags lus
  - gf_mode
- Dépendances dures
  - gf_core
- Dépendances optionnelles
  - gf_admin
  - gf_attack
- Dette
  - cycle:gf_attack

## gf_maps

- Exports fournis
  - GetActiveMaps
  - GetMaps
- Exports consommés
  - gf_admin:LogAction
- Événements émis
  - gf_lobby:menuOverlay
- Événements écoutés
  - gf_core:modeChanged
  - gf_lobby:state
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_core
- Dépendances optionnelles
  - gf_admin
- Dette
  - Aucun.

## gf_menu

- Exports fournis
  - Aucun.
- Exports consommés
  - gf_core:GetMode
  - gf_core:IsAdmin
  - gf_stats:GetPlayerStats
  - gf_thumbs:Get
- Événements émis
  - gf_admin:open
  - gf_inventory:adminGive
  - gf_inventory:equip
  - gf_inventory:requestLocker
  - gf_inventory:setAccessories
  - gf_lobby:menuOverlay
- Événements écoutés
  - gf_core:modeChanged
  - gf_core:spawned
  - gf_inventory:accessoriesSaved
  - gf_inventory:adminData
  - gf_inventory:locker
  - gf_inventory:openAdmin
  - gf_lobby:state
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_core
  - gf_stats
- Dépendances optionnelles
  - gf_thumbs
- Dette
  - Aucun.

## gf_redzone

- Exports fournis
  - AllowDamage
  - CanChangeWeapons
- Exports consommés
  - gf_admin:LogAction
  - gf_core:DeleteModeVehicle
  - gf_core:GiveModeVehicle
  - gf_killcam:RemainingMs
  - gf_maps:GetActiveMaps
- Événements émis
  - gf:healGranted
  - gf:matchEnded
  - gf:matchResults
  - gf:matchStarted
  - gf:modeKill
  - gf:phase
  - gf_ui:announce
  - gf_ui:hud
  - gf_ui:scoreboard
  - gf_ui:scoreboard_show
- Événements écoutés
  - gf:modeJoined
  - gf:modeLeft
  - gf:playerKilled
  - gf_core:modeChanged
  - gf_core:spawned
  - gf_inventory:selectionChanged
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_core
  - gf_maps
  - gf_ui
- Dépendances optionnelles
  - gf_admin
  - gf_killcam
- Dette
  - Aucun.

## gf_screen

- Exports fournis
  - Aucun.
- Exports consommés
  - gf_admin:LogAction
  - gf_core:GetWeaponThumbList
- Événements émis
  - Aucun.
- Événements écoutés
  - Aucun.
- State bags écrits
  - Aucun.
- State bags lus
  - gf_mode
- Dépendances dures
  - gf_admin
  - gf_core
- Dépendances optionnelles
  - gf_admin
- Dette
  - Aucun.

## gf_stats

- Exports fournis
  - GetPlayerStats
- Exports consommés
  - gf_db:Pret
- Événements émis
  - Aucun.
- Événements écoutés
  - gf:matchEnded
  - gf:modeKill
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - gf_db
  - oxmysql
- Dépendances optionnelles
  - Aucun.
- Dette
  - Aucun.

## gf_thumbs

- Exports fournis
  - Get
- Exports consommés
  - gf_vehicles:ApplyCustom
- Événements émis
  - Aucun.
- Événements écoutés
  - gf_core:modeChanged
- State bags écrits
  - Aucun.
- State bags lus
  - gf_mode
- Dépendances dures
  - Aucun.
- Dépendances optionnelles
  - gf_vehicles
- Dette
  - cycle:gf_vehicles

## gf_ui

- Exports fournis
  - Aucun.
- Exports consommés
  - gf_thumbs:Get
- Événements émis
  - gf:loadoutChosen
- Événements écoutés
  - gf_thumbs:updated
- State bags écrits
  - Aucun.
- State bags lus
  - gf_mode
- Dépendances dures
  - Aucun.
- Dépendances optionnelles
  - gf_thumbs
- Dette
  - Aucun.

## gf_vehicles

- Exports fournis
  - ApplyCustom
  - GetThumbList
- Exports consommés
  - gf_admin:LogAction
  - gf_thumbs:Get
- Événements émis
  - gf_lobby:menuOverlay
- Événements écoutés
  - gf_core:modeChanged
  - gf_lobby:state
- State bags écrits
  - gf_vehicle_base
  - gf_vehicle_customs
  - gf_vehicle_versions
- State bags lus
  - gf_vehicle_customs
  - gf_vehicle_versions
- Dépendances dures
  - Aucun.
- Dépendances optionnelles
  - gf_admin
  - gf_thumbs
- Dette
  - cycle:gf_thumbs

## gf_weapons

- Exports fournis
  - Aucun.
- Exports consommés
  - Aucun.
- Événements émis
  - Aucun.
- Événements écoutés
  - Aucun.
- State bags écrits
  - Aucun.
- State bags lus
  - Aucun.
- Dépendances dures
  - Aucun.
- Dépendances optionnelles
  - Aucun.
- Dette
  - Aucun.

## Propriétaires des événements `gf:*`

| Événement | Émetteurs | Écouteurs |
| --- | --- | --- |
| gf:anomalie | gf_audit, gf_core | gf_journal |
| gf:armourGranted | gf_core | gf_audit |
| gf:healGranted | gf_admin, gf_redzone | gf_audit |
| gf:hit | gf_core | gf_audit, gf_journal |
| gf:itemUsed | gf_attack | gf_audit |
| gf:loadoutChosen | gf_ui | gf_attack |
| gf:matchAborted | gf_attack | gf_journal |
| gf:matchEnded | gf_attack, gf_redzone | gf_journal, gf_stats |
| gf:matchResults | gf_attack, gf_redzone | gf_journal |
| gf:matchStarted | gf_attack, gf_redzone | gf_journal |
| gf:modeJoined | gf_core | gf_attack, gf_journal, gf_lobby, gf_redzone |
| gf:modeKill | gf_attack, gf_redzone | gf_journal, gf_stats |
| gf:modeLeft | gf_core | gf_attack, gf_audit, gf_journal, gf_killcam, gf_lobby, gf_redzone |
| gf:phase | gf_attack, gf_redzone | gf_journal |
| gf:playerKilled | gf_core | gf_attack, gf_audit, gf_journal, gf_killcam, gf_redzone |
| gf:roundEnded | gf_attack | gf_journal |
| gf:spawned | gf_core | gf_audit |
