"""Contrat d'événements client → serveur du dépôt FiveMGunFight.

Ces tests ne démarrent pas le serveur. Ils figent la surface d'événements
réseau : tout `TriggerServerEvent` émis par un script client doit avoir un
`RegisterNetEvent` côté serveur, et tout événement serveur doit être documenté
dans docs/evenements-serveur.md avec sa validation, son rate-limit et son
éventuel accès administrateur.

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
RESSOURCES = RACINE / "server-data" / "resources"
DOCUMENTATION = RACINE / "docs" / "evenements-serveur.md"
CORE = RESSOURCES / "[gunfight]" / "gf_core"
MAPS = RESSOURCES / "[gunfight]" / "gf_maps"

MOTS_SERVEUR = ("server_script", "server_scripts")
MOTS_CLIENT = ("client_script", "client_scripts")
MOTS_PARTAGES = ("shared_script", "shared_scripts")

MOTIF_REGISTER = re.compile(r"""RegisterNetEvent\s*\(\s*['"]([^'"]+)['"]""")
MOTIF_TRIGGER_SERVEUR = re.compile(r"""TriggerServerEvent\s*\(\s*['"]([^'"]+)['"]""")
MOTIF_COMMENTAIRE_BLOC = re.compile(r"--\[\[.*?\]\]", re.DOTALL)
MOTIF_COMMENTAIRE_LIGNE = re.compile(r"--[^\n]*")
MOTIF_LIGNE_TABLEAU = re.compile(r"^\|\s*`([^`]+)`\s*\|")

# Événements serveur attendus, y compris ceux fournis par cfx-default.
EVENEMENTS_ATTENDUS = (
    "gf_core:ready",
    "gf_core:vehicle",
    "gf_core:vehicleGone",
    "gf_maps:save",
    "gf_maps:setEnabled",
    "gf_maps:delete",
    "baseevents:onPlayerKilled",
    "baseevents:onPlayerDied",
    "baseevents:onPlayerWasted",
    "baseevents:enteringVehicle",
    "baseevents:enteringAborted",
    "baseevents:enteredVehicle",
    "baseevents:leftVehicle",
)

COLONNES_DOCUMENTATION = (
    "événement",
    "émetteur",
    "validation",
    "rate-limit",
    "admin requis",
    "notes",
)


def lire(chemin: Path) -> str:
    return chemin.read_text(encoding="utf-8")


def sans_commentaires(texte: str) -> str:
    """Retire les commentaires Lua pour ne pas compter du code commenté."""
    texte = MOTIF_COMMENTAIRE_BLOC.sub("", texte)
    return MOTIF_COMMENTAIRE_LIGNE.sub("", texte)


def scripts_declares(manifeste: Path, mots: tuple[str, ...]) -> list[Path]:
    """Chemins déclarés par un fxmanifest pour les mots-clés donnés."""
    texte = sans_commentaires(lire(manifeste))
    chemins: list[Path] = []
    for mot in mots:
        motif = rf"\b{mot}\b\s*(\{{[^}}]*\}}|'[^']*'|\"[^\"]*\")"
        for trouve in re.finditer(motif, texte):
            for simple, double in re.findall(r"'([^']+)'|\"([^\"]+)\"", trouve.group(1)):
                nom = simple or double
                if nom:
                    chemins.append(manifeste.parent / nom)
    return chemins


def scripts_du_depot(mots: tuple[str, ...]) -> list[Path]:
    manifestes = sorted(RESSOURCES.glob("*/*/fxmanifest.lua"))
    fichiers: set[Path] = set()
    for manifeste in manifestes:
        # [standalone] : ressources tierces vendorisées (oxmysql, game 'common').
        # Leurs événements internes ne font pas partie du contrat du dépôt.
        if manifeste.parent.parent.name == "[standalone]":
            continue
        fichiers.update(scripts_declares(manifeste, mots))
    return sorted(fichiers)


def evenements(fichiers: list[Path], motif: re.Pattern[str]) -> dict[str, set[str]]:
    trouves: dict[str, set[str]] = {}
    for fichier in fichiers:
        for nom in motif.findall(sans_commentaires(lire(fichier))):
            trouves.setdefault(nom, set()).add(str(fichier.relative_to(RACINE)))
    return trouves


def evenements_documentes() -> dict[str, int]:
    """Événements présents en première colonne d'un tableau Markdown."""
    documentes: dict[str, int] = {}
    for numero, ligne in enumerate(lire(DOCUMENTATION).splitlines(), 1):
        trouve = MOTIF_LIGNE_TABLEAU.match(ligne)
        if trouve:
            documentes[trouve.group(1)] = numero
    return documentes


def bloc_handler(texte: str, nom: str) -> str | None:
    """Bloc d'un handler, de son RegisterNetEvent au suivant."""
    motif = re.compile(
        rf"RegisterNetEvent\s*\(\s*['\"]{re.escape(nom)}['\"].*?"
        r"(?=\nRegisterNetEvent\s*\(|\Z)",
        re.DOTALL,
    )
    trouve = motif.search(texte)
    return trouve.group(0) if trouve else None


class ContratEvenements(unittest.TestCase):
    """La surface réseau est complète, documentée et garde ses protections."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.scripts_serveur = scripts_du_depot(MOTS_SERVEUR + MOTS_PARTAGES)
        cls.scripts_client = scripts_du_depot(MOTS_CLIENT + MOTS_PARTAGES)
        cls.registres = evenements(cls.scripts_serveur, MOTIF_REGISTER)
        cls.emissions = evenements(cls.scripts_client, MOTIF_TRIGGER_SERVEUR)
        cls.documentes = evenements_documentes()

    def test_scripts_scannes_non_vides(self) -> None:
        self.assertTrue(self.scripts_serveur, "aucun script serveur déclaré")
        self.assertTrue(self.scripts_client, "aucun script client déclaré")
        self.assertIn(CORE / "server.lua", self.scripts_serveur)
        self.assertIn(CORE / "client.lua", self.scripts_client)

    def test_evenements_reellement_presents_recenses(self) -> None:
        for nom in EVENEMENTS_ATTENDUS:
            with self.subTest(evenement=nom):
                self.assertIn(nom, self.registres, "événement serveur non détecté")
        for nom in ("gf_core:ready", "gf_core:vehicle", "gf_core:vehicleGone"):
            with self.subTest(evenement=nom):
                self.assertIn(nom, self.emissions, "émission client non détectée")

    def test_chaque_event_client_vers_serveur_a_un_handler(self) -> None:
        for nom, fichiers in sorted(self.emissions.items()):
            with self.subTest(evenement=nom):
                self.assertIn(
                    nom,
                    self.registres,
                    f"{nom} est émis par {sorted(fichiers)} mais aucun RegisterNetEvent serveur",
                )

    def test_chaque_event_serveur_est_documente(self) -> None:
        for nom, fichiers in sorted(self.registres.items()):
            with self.subTest(evenement=nom):
                self.assertIn(
                    nom,
                    self.documentes,
                    f"{nom} (déclaré dans {sorted(fichiers)}) est absent de docs/evenements-serveur.md",
                )

    def test_table_de_documentation_complete(self) -> None:
        lignes = lire(DOCUMENTATION).splitlines()
        entete = next((ligne for ligne in lignes if ligne.lstrip().startswith("|") and "Événement" in ligne), None)
        self.assertIsNotNone(entete, "en-tête du tableau d'événements absent")
        colonnes = [colonne.strip().lower() for colonne in entete.strip().strip("|").split("|")]
        for attendue in COLONNES_DOCUMENTATION:
            with self.subTest(colonne=attendue):
                self.assertIn(attendue, colonnes, "colonne attendue absente du tableau")

        for nom, numero in sorted(self.documentes.items()):
            ligne = lignes[numero - 1]
            cellules = [cellule.strip() for cellule in ligne.strip().strip("|").split("|")]
            with self.subTest(evenement=nom, ligne=numero):
                self.assertGreaterEqual(len(cellules), 6, "ligne d'événement incomplète")
                for indice, valeur in enumerate(cellules[:6]):
                    self.assertTrue(valeur, f"colonne {indice + 1} vide pour {nom}")
                self.assertIn(cellules[4].lower(), ("oui", "non"), "colonne admin requis : oui ou non")

    def test_events_admin_gf_maps_appellent_isadmin(self) -> None:
        texte = lire(MAPS / "server.lua")
        for nom in ("gf_maps:save", "gf_maps:setEnabled", "gf_maps:delete"):
            with self.subTest(evenement=nom):
                bloc = bloc_handler(texte, nom)
                self.assertIsNotNone(bloc, f"handler {nom} introuvable")
                self.assertIn("core:IsAdmin(src)", bloc, f"{nom} doit vérifier les droits admin")

    def test_baseevents_onplayerKilled_n_utilise_plus_killerid(self) -> None:
        texte = sans_commentaires(lire(CORE / "server.lua"))
        bloc = bloc_handler(texte, "baseevents:onPlayerKilled")
        self.assertIsNotNone(bloc, "handler baseevents:onPlayerKilled introuvable")
        self.assertNotRegex(bloc, r"(?i)\bkillerid\b", "le killerId client ne doit plus être utilisé")
        self.assertIn("handleDeath(source", bloc, "le handler doit dériver la mort côté serveur")

    def test_vehicle_a_les_garde_fous_serveur(self) -> None:
        texte = sans_commentaires(lire(CORE / "server.lua"))
        validation = sans_commentaires(lire(CORE / "validation.lua"))
        bloc = bloc_handler(texte, "gf_core:vehicle")
        self.assertIsNotNone(bloc, "handler gf_core:vehicle introuvable")
        self.assertIn("verifierVehicule(src, netId)", bloc, "validation absente du handler")
        self.assertIn("Validation.verifierVehicule", texte, "module de validation non appelé")
        self.assertIn("autoriserRate", bloc, "rate-limit absent du handler")

        for garde_fou in ("NetworkGetEntityOwner", "GetEntityType", "Config.VehicleBindDistance"):
            with self.subTest(garde_fou=garde_fou):
                self.assertIn(garde_fou, texte, "garde-fou natif absent de server.lua")
        self.assertIn("RateLimit.autoriser", texte, "rate-limit serveur absent")
        for reglage in ("Config.VehicleRateLimit", "Config.VehicleGoneRateLimit", "Config.ReadyRateLimit"):
            with self.subTest(reglage=reglage):
                self.assertIn(reglage, texte, "constante de rate-limit absente")

        for regle in ("deps.entityType(entite) ~= 2", "deps.entityOwner(entite) ~= joueur", "distance > maximum"):
            with self.subTest(regle=regle):
                self.assertIn(regle, validation, "règle de validation absente")

    def test_vehicleGone_et_ready_ont_un_rate_limit(self) -> None:
        texte = sans_commentaires(lire(CORE / "server.lua"))
        for nom in ("gf_core:vehicleGone", "gf_core:ready"):
            with self.subTest(evenement=nom):
                bloc = bloc_handler(texte, nom)
                self.assertIsNotNone(bloc, f"handler {nom} introuvable")
                self.assertIn("autoriserRate", bloc, f"{nom} doit être rate-limité")

    def test_documentation_explique_les_garde_fous(self) -> None:
        texte = lire(DOCUMENTATION)
        for garde_fou in (
            "Config.VehicleBindDistance",
            "Config.KillCreditWindow",
            "Config.ValidateDeathHealth",
            "lastDamager",
        ):
            with self.subTest(garde_fou=garde_fou):
                self.assertIn(garde_fou, texte, "garde-fou non expliqué dans la documentation")

        for nom in ("baseevents:onPlayerWasted", "baseevents:enteringVehicle", "baseevents:leftVehicle"):
            with self.subTest(evenement=nom):
                self.assertIn(nom, self.documentes, "événement cfx-default non documenté")


if __name__ == "__main__":
    unittest.main()
