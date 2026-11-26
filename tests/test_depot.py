"""Tests de cohérence du dépôt FiveMGunFight.

Ces tests ne démarrent pas le serveur : le job « Docker » de la CI s'en charge
(construction de l'image puis démarrage réel des ressources). Ils vérifient que
les fichiers du dépôt restent cohérents entre eux, pour qu'une pull request ne
puisse pas casser silencieusement les manifestes, les maps, la configuration ou
la documentation.

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import json
import math
import re
import shutil
import subprocess
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
RESSOURCES = RACINE / "server-data" / "resources"
RESSOURCES_GUNFIGHT = ("gf_core", "gf_ui", "gf_maps", "gf_attack", "gf_redzone", "gf_lobby", "gf_stats", "gf_vehicles", "gf_thumbs")
MAPS_JSON = RESSOURCES / "[gunfight]" / "gf_maps" / "data" / "maps.json"

MOTS_SCRIPTS = (
    "client_script",
    "client_scripts",
    "server_script",
    "server_scripts",
    "shared_script",
    "shared_scripts",
    "ui_page",
    "files",
)


def lire(chemin: Path) -> str:
    return chemin.read_text(encoding="utf-8")


def dossiers_ressources() -> list[Path]:
    return sorted(p for p in RESSOURCES.glob("*/*") if p.is_dir())


def manifestes() -> list[Path]:
    return sorted(RESSOURCES.glob("*/*/fxmanifest.lua"))


def chemins_declares(manifeste: Path) -> set[str]:
    """Chemins de fichiers cités par un fxmanifest (scripts, ui_page, files)."""
    texte = lire(manifeste)
    chemins: set[str] = set()
    for mot in MOTS_SCRIPTS:
        motif = rf"\b{mot}\b\s*(\{{[^}}]*\}}|'[^']*'|\"[^\"]*\")"
        for trouve in re.finditer(motif, texte):
            bloc = trouve.group(1)
            for simple, double in re.findall(r"'([^']+)'|\"([^\"]+)\"", bloc):
                chemin = simple or double
                if chemin:
                    chemins.add(chemin)
    return chemins


def cles_env(chemin: Path) -> dict[str, str]:
    valeurs: dict[str, str] = {}
    for ligne in lire(chemin).splitlines():
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#") or "=" not in ligne:
            continue
        cle, valeur = ligne.split("=", 1)
        valeurs[cle.strip()] = valeur.strip()
    return valeurs


def est_nombre(valeur: object) -> bool:
    return (
        isinstance(valeur, (int, float))
        and not isinstance(valeur, bool)
        and math.isfinite(float(valeur))
    )


def bloc_service(texte: str, nom: str) -> str | None:
    """Bloc d'un service ou d'un job (clé indentée de deux espaces)."""
    trouve = re.search(
        rf"(?ms)^  {re.escape(nom)}:\s*$.*?(?=^  [a-z][\w-]*:\s*$|^[a-z][\w-]*:\s*$|\Z)",
        texte,
    )
    return trouve.group(0) if trouve else None


def volumes_declares(texte: str) -> dict[str, str]:
    """Bloc racine `volumes:` : nom logique -> nom explicite (chaîne vide si absent)."""
    section = re.search(r"(?ms)^volumes:\s*\n(.*?)(?=^[a-z][\w-]*:\s*$|\Z)", texte)
    if section is None:
        return {}
    volumes: dict[str, str] = {}
    courant = ""
    for ligne in section.group(1).splitlines():
        trouve = re.match(r"^  ([a-z][\w-]*):\s*(?:#.*)?$", ligne)
        if trouve:
            courant = trouve.group(1)
            volumes[courant] = ""
            continue
        nom = re.match(r"^    name:\s*(\S+)\s*$", ligne)
        if nom and courant:
            volumes[courant] = nom.group(1)
    return volumes


class ManifestesFiveM(unittest.TestCase):
    """Les ressources doivent être déclarées correctement pour démarrer."""

    def test_chaque_ressource_a_un_manifeste(self) -> None:
        sans_manifeste = [
            str(d.relative_to(RACINE)) for d in dossiers_ressources()
            if not (d / "fxmanifest.lua").is_file()
        ]
        self.assertEqual([], sans_manifeste, "un dossier de ressource n'a pas de fxmanifest.lua")

    def test_manifeste_declare_version_et_jeu(self) -> None:
        for manifeste in manifestes():
            # [standalone] : ressource tierce vendorisée (oxmysql, game 'common').
            if manifeste.parent.parent.name == "[standalone]":
                continue
            texte = lire(manifeste)
            with self.subTest(manifeste=str(manifeste.relative_to(RACINE))):
                self.assertRegex(texte, r"fx_version\s+'cerulean'", "fx_version attendu")
                self.assertRegex(texte, r"\bgame\s+'gta5'|\bgames\s*\{", "jeu non déclaré")

    def test_fichiers_declares_existent(self) -> None:
        for manifeste in manifestes():
            # [standalone] : ressource tierce vendorisée (oxmysql, game 'common').
            if manifeste.parent.parent.name == "[standalone]":
                continue
            for chemin in chemins_declares(manifeste):
                with self.subTest(manifeste=str(manifeste.relative_to(RACINE)), chemin=chemin):
                    self.assertTrue(
                        (manifeste.parent / chemin).is_file(),
                        f"fichier déclaré introuvable : {chemin}",
                    )

    def test_ressources_gunfight_listees_dans_les_manifestes(self) -> None:
        noms = {m.parent.name for m in manifestes()}
        for ressource in RESSOURCES_GUNFIGHT:
            with self.subTest(ressource=ressource):
                self.assertIn(ressource, noms)


class ConfigurationServeur(unittest.TestCase):
    """server.cfg, .env.example et fichiers ignorés restent cohérents."""

    def test_server_cfg_demarre_les_ressources_gunfight(self) -> None:
        texte = lire(RACINE / "server-data" / "server.cfg")
        assurees = re.findall(r"^\s*ensure\s+(\S+)", texte, re.MULTILINE)
        for ressource in RESSOURCES_GUNFIGHT:
            with self.subTest(ressource=ressource):
                self.assertIn(ressource, assurees, "ressource absente de server.cfg")
                self.assertTrue(
                    (RESSOURCES / "[gunfight]" / ressource).is_dir(),
                    "ressource assurée mais absente du dépôt",
                )

    def test_server_cfg_n_assure_pas_de_ressource_supprimee(self) -> None:
        texte = lire(RACINE / "server-data" / "server.cfg")
        assurees = re.findall(r"^\s*ensure\s+(\S+)", texte, re.MULTILINE)
        for disparue in ("sessionmanager", "hardcap"):
            with self.subTest(ressource=disparue):
                self.assertNotIn(
                    disparue, assurees,
                    "ressource supprimée de FXServer : le serveur refuserait de démarrer",
                )

    def test_env_exemple_contient_les_cles_requises(self) -> None:
        valeurs = cles_env(RACINE / ".env.example")
        for cle in (
            "LICENSE_KEY",
            "SERVER_NAME",
            "MAX_PLAYERS",
            "MARIADB_ROOT_PASSWORD",
            "MARIADB_DATABASE",
            "MARIADB_USER",
            "MARIADB_PASSWORD",
        ):
            with self.subTest(cle=cle):
                self.assertIn(cle, valeurs, "clé absente de .env.example")

    def test_env_exemple_ne_contient_aucun_secret(self) -> None:
        valeurs = cles_env(RACINE / ".env.example")
        self.assertEqual("change_moi", valeurs.get("LICENSE_KEY"))
        for cle, valeur in valeurs.items():
            if "PASSWORD" in cle:
                with self.subTest(cle=cle):
                    self.assertTrue(
                        valeur.startswith("change_moi"),
                        "un mot de passe réel semble présent dans .env.example",
                    )

    def test_gitignore_protege_les_secrets(self) -> None:
        lignes = {
            ligne.strip()
            for ligne in lire(RACINE / ".gitignore").splitlines()
            if ligne.strip() and not ligne.startswith("#")
        }
        for motif in (".env", "server-data/secrets.cfg", "server-data/cache/"):
            with self.subTest(motif=motif):
                self.assertIn(motif, lignes)

    def test_dockerignore_exclut_secrets_et_cache(self) -> None:
        lignes = {ligne.strip() for ligne in lire(RACINE / ".dockerignore").splitlines()}
        for motif in (".env", "server-data/secrets.cfg", "server-data/cache/"):
            with self.subTest(motif=motif):
                self.assertIn(motif, lignes)


class InfraDocker(unittest.TestCase):
    """Les garde-fous d'exploitation (lot 1 du durcissement) restent en place."""

    COMPOSE = RACINE / "docker-compose.yml"
    ENTRYPOINT = RACINE / "docker" / "entrypoint.sh"

    def service(self, nom: str) -> str:
        """Texte d'un service Compose (bloc indenté de deux espaces)."""
        texte = lire(self.COMPOSE)
        bloc = re.search(
            rf"(?ms)^  {nom}:\s*$.*?(?=^  [a-z][\w-]*:\s*$|^[a-z][\w-]*:\s*$|\Z)",
            texte,
        )
        self.assertIsNotNone(bloc, f"service {nom} absent de docker-compose.yml")
        return bloc.group(0)

    def test_txadmin_n_est_joignable_que_depuis_la_machine(self) -> None:
        texte = lire(self.COMPOSE)
        self.assertIn("127.0.0.1:40120:40120/tcp", texte)
        self.assertNotRegex(texte, r'(?m)^\s*-\s*"40120:40120/tcp"')

    def test_fxserver_a_un_healthcheck(self) -> None:
        bloc = self.service("fxserver")
        self.assertIn("healthcheck:", bloc)
        self.assertIn("30120/dynamic.json", bloc)
        self.assertIn("start_period: 120s", bloc)

    def test_services_ont_une_limite_memoire(self) -> None:
        self.assertIn("mem_limit: ${FXSERVER_MEMORY_LIMIT:-4g}", self.service("fxserver"))
        self.assertIn("mem_limit: ${MARIADB_MEMORY_LIMIT:-2g}", self.service("mariadb"))

    def test_nom_de_projet_compose_fixe(self) -> None:
        self.assertRegex(lire(self.COMPOSE), r"(?m)^name:\s+gunfight\s*$")

    def test_secrets_cfg_est_protege(self) -> None:
        texte = lire(self.ENTRYPOINT)
        self.assertIn("umask 077", texte)
        self.assertIn('chmod 600 "$DATA/secrets.cfg"', texte)

    def test_limites_memoire_sont_documentees(self) -> None:
        texte = lire(RACINE / ".env.example")
        for cle in ("FXSERVER_MEMORY_LIMIT", "MARIADB_MEMORY_LIMIT"):
            with self.subTest(cle=cle):
                self.assertIn(cle, texte, "variable absente de .env.example")

    def test_dockerfile_from_est_epingle_par_digest(self) -> None:
        texte = lire(RACINE / "Dockerfile")
        self.assertRegex(
            texte,
            r"(?m)^FROM\s+\S+@sha256:[0-9a-f]{64}\s*$",
            "l'image de base doit être épinglée par digest",
        )

    def test_image_mariadb_est_epinglee_par_digest(self) -> None:
        self.assertRegex(
            self.service("mariadb"),
            r"(?m)^\s+image:\s*mariadb:11\.4@sha256:[0-9a-f]{64}\s*$",
            "MariaDB doit être épinglée par digest dans le socle",
        )

    def test_entrypoint_amorce_les_maps(self) -> None:
        texte = lire(self.ENTRYPOINT)
        for nom in ("GF_SEED_MAPS", "MAPS_DEFAUT"):
            with self.subTest(nom=nom):
                self.assertIn(nom, texte, "amorçage de maps.json incomplet")


class EnvironnementsCompose(unittest.TestCase):
    """Le découpage socle / dev / prod reste utilisable sans ambiguïté.

    Le socle ne se lance jamais seul : le dev ajoute la construction locale et
    le montage des scripts, la prod ajoute l'image publiée et ses volumes.
    """

    SOCLE = RACINE / "docker-compose.yml"
    DEV = RACINE / "docker-compose.dev.yml"
    PROD = RACINE / "docker-compose.prod.yml"

    def bloc(self, chemin: Path, nom: str) -> str:
        bloc = bloc_service(lire(chemin), nom)
        if bloc is None:
            self.fail(f"service {nom} absent de {chemin.name}")
        return bloc

    def test_les_trois_fichiers_compose_existent(self) -> None:
        for fichier in (self.SOCLE, self.DEV, self.PROD):
            with self.subTest(fichier=fichier.name):
                self.assertTrue(fichier.is_file(), "fichier Compose manquant")
                self.assertGreater(
                    len(lire(fichier).strip()), 100, "fichier Compose vide ou presque"
                )

    def test_dev_construit_l_image_et_monte_les_scripts(self) -> None:
        bloc = self.bloc(self.DEV, "fxserver")
        self.assertRegex(
            bloc,
            r"(?m)^\s+build:\s*(\.\s*$|\n\s+context:\s*\.\s*$)",
            "build local absent",
        )
        self.assertIn(
            "./server-data:/opt/fivem/server-data",
            bloc,
            "les scripts du dépôt ne sont pas montés en dev",
        )
        self.assertRegex(
            bloc,
            r"(?m)^\s+BUILD_SHA:\s*\$\{BUILD_SHA:-dev\}\s*$",
            "le dev doit transmettre le sha du build (valeur de repli « dev »)",
        )

    def test_dev_garde_les_volumes_du_socle(self) -> None:
        self.assertEqual(
            {},
            volumes_declares(lire(self.DEV)),
            "le dev ne doit pas renommer les volumes (installation existante)",
        )

    def test_prod_utilise_l_image_publiee_et_le_volume_maps(self) -> None:
        bloc = self.bloc(self.PROD, "fxserver")
        self.assertIn("image: ${IMAGE_REF", bloc, "IMAGE_REF absente de la surcouche prod")
        self.assertIn(
            "/opt/fivem/server-data/resources/[gunfight]/gf_maps/data",
            bloc,
            "le volume maps n'est pas monté au bon endroit",
        )
        self.assertNotIn(
            "./server-data:",
            lire(self.PROD),
            "la production ne doit pas monter le dossier du dépôt",
        )

    def test_prod_active_l_amorcage_des_maps(self) -> None:
        bloc = self.bloc(self.PROD, "fxserver")
        self.assertRegex(bloc, r'GF_SEED_MAPS:\s*"?true"?', "GF_SEED_MAPS doit valoir true")

    def test_prod_volumes_sont_nommes_et_distincts_du_dev(self) -> None:
        prod = volumes_declares(lire(self.PROD))
        dev = lire(self.DEV)
        socle = lire(self.SOCLE)
        for volume, nom in (
            ("txdata", "gunfight-prod-txdata"),
            ("dbdata", "gunfight-prod-dbdata"),
            ("maps", "gunfight-prod-maps"),
            ("characters", "gunfight-prod-characters"),
        ):
            with self.subTest(volume=volume):
                self.assertEqual(prod.get(volume), nom, "volume de production mal nommé")
                self.assertNotIn(nom, dev, "volume de production présent dans le dev")
                self.assertNotIn(nom, socle, "volume de production présent dans le socle")

    def test_socle_n_a_pas_de_build_ni_d_image_pour_fxserver(self) -> None:
        bloc = self.bloc(self.SOCLE, "fxserver")
        self.assertNotRegex(bloc, r"(?m)^\s+build:", "le socle ne doit pas construire d'image")
        self.assertNotRegex(bloc, r"(?m)^\s+image:", "le socle ne doit pas choisir d'image")


class StatistiquesPersistantes(unittest.TestCase):
    """gf_stats, oxmysql et les événements de statistiques restent câblés."""

    def test_server_cfg_demarre_oxmysql_avant_gf_stats(self) -> None:
        texte = lire(RACINE / "server-data" / "server.cfg")
        ox = texte.find("ensure oxmysql")
        stats = texte.find("ensure gf_stats")
        self.assertGreaterEqual(ox, 0, "ensure oxmysql absent")
        self.assertGreater(stats, ox, "gf_stats doit démarrer après oxmysql")

    def test_schema_cree_la_table_gf_stats_players(self) -> None:
        texte = lire(RACINE / "docker" / "db" / "init" / "01-schema.sql")
        self.assertIn("CREATE TABLE IF NOT EXISTS gf_stats_players", texte)

    def test_oxmysql_vendorise_present(self) -> None:
        base = RESSOURCES / "[standalone]" / "oxmysql"
        for nom in ("fxmanifest.lua", "LICENSE"):
            with self.subTest(fichier=nom):
                self.assertTrue((base / nom).is_file(), "fichier oxmysql manquant")

    def test_gf_stats_depend_de_oxmysql(self) -> None:
        texte = lire(RESSOURCES / "[gunfight]" / "gf_stats" / "fxmanifest.lua")
        self.assertRegex(texte, r"dependency\s+'oxmysql'")

    def test_les_modes_emettent_les_evenements_de_stats(self) -> None:
        for mode in ("gf_attack", "gf_redzone"):
            texte = lire(RESSOURCES / "[gunfight]" / mode / "server.lua")
            with self.subTest(mode=mode):
                self.assertIn("gf:modeKill", texte)
                self.assertIn("gf:matchEnded", texte)

    def test_prod_monte_le_volume_characters(self) -> None:
        texte = lire(RACINE / "docker-compose.prod.yml")
        self.assertIn(
            "characters:/opt/fivem/server-data/resources/[gunfight]/gf_lobby/data",
            texte,
            "volume characters absent de la production",
        )


class MapsEnJeu(unittest.TestCase):
    """Le format de data/maps.json doit rester celui attendu par les modes."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.donnees = json.loads(lire(MAPS_JSON))

    def test_sections_attendues(self) -> None:
        self.assertIsInstance(self.donnees.get("redzone"), list)
        self.assertIsInstance(self.donnees.get("attack"), list)

    def test_redzones_valides(self) -> None:
        for carte in self.donnees["redzone"]:
            with self.subTest(carte=carte.get("id")):
                for cle in ("id", "name", "radius", "center", "spawns"):
                    self.assertIn(cle, carte)
                self.assertTrue(est_nombre(carte["radius"]) and carte["radius"] > 0, "rayon invalide")
                self.assertTrue(all(est_nombre(carte["center"].get(a)) for a in "xyz"))
                self.assertTrue(carte["spawns"], "une redzone sans point d'apparition")
                for apparition in carte["spawns"]:
                    self.assertTrue(all(est_nombre(apparition.get(a)) for a in "xyz"))

    def test_zones_attaque_valides(self) -> None:
        for zone in self.donnees["attack"]:
            with self.subTest(zone=zone.get("id")):
                for cle in ("id", "name", "points", "attackSpawn", "defenseSpawn"):
                    self.assertIn(cle, zone)
                self.assertGreaterEqual(len(zone["points"]), 3, "un polygone a au moins 3 sommets")
                for point in zone["points"]:
                    self.assertTrue(all(est_nombre(point.get(a)) for a in "xyz"))
                for cle in ("attackSpawn", "defenseSpawn"):
                    self.assertTrue(all(est_nombre(zone[cle].get(a)) for a in "xyz"))

    def test_identifiants_uniques(self) -> None:
        identifiants = [c["id"] for c in self.donnees["redzone"] + self.donnees["attack"]]
        self.assertEqual(len(identifiants), len(set(identifiants)), "identifiant de map dupliqué")


class Documentation(unittest.TestCase):
    """La documentation attendue doit exister et rester à jour."""

    DOCUMENTS = (
        "README.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "docs/README.md",
        "docs/architecture.md",
        "docs/lobby.md",
        "docs/qualite.md",
        "docs/protection-branche.md",
        ".github/pull_request_template.md",
        ".github/CODEOWNERS",
    )

    def test_documents_presents_et_remplis(self) -> None:
        for document in self.DOCUMENTS:
            with self.subTest(document=document):
                chemin = RACINE / document
                self.assertTrue(chemin.is_file(), "document manquant")
                self.assertGreater(len(lire(chemin).strip()), 200, "document vide ou presque")

    def test_readme_cite_chaque_ressource(self) -> None:
        texte = lire(RACINE / "README.md")
        for ressource in RESSOURCES_GUNFIGHT:
            with self.subTest(ressource=ressource):
                self.assertIn(ressource, texte)

    def test_workflows_declarent_declencheurs_et_jobs(self) -> None:
        workflows = sorted((RACINE / ".github" / "workflows").glob("*.yml"))
        self.assertTrue(workflows, "aucun workflow GitHub Actions")
        for workflow in workflows:
            texte = lire(workflow)
            with self.subTest(workflow=workflow.name):
                self.assertRegex(texte, r"(?m)^on:")
                self.assertRegex(texte, r"(?m)^jobs:")


class ChaineCI(unittest.TestCase):
    """La CI reste verrouillée, exécutée sur les PR et à jour de ses dépendances."""

    GITHUB = RACINE / ".github"
    WORKFLOWS = GITHUB / "workflows"
    DEPENDABOT = GITHUB / "dependabot.yml"
    PROTECTION = GITHUB / "branch-protection.json"
    NOM_SMOKE = "Vérifier le démarrage des ressources"

    def workflows(self) -> list[Path]:
        return sorted(self.WORKFLOWS.glob("*.yml"))

    def blocs_jobs(self, chemin: Path) -> dict[str, str]:
        """Bloc texte de chaque job d'un workflow, indexé par son identifiant."""
        texte = lire(chemin)
        section = re.search(r"(?ms)^jobs:\s*\n(.*)", texte)
        if section is None:
            self.fail(f"section jobs absente de {chemin.name}")
        noms = re.findall(r"(?m)^  ([a-z][\w-]*):\s*$", section.group(1))
        self.assertTrue(noms, f"aucun job dans {chemin.name}")
        blocs: dict[str, str] = {}
        for nom in noms:
            bloc = bloc_service(texte, nom)
            if bloc is None:
                self.fail(f"job {nom} illisible dans {chemin.name}")
            blocs[nom] = bloc
        return blocs

    def test_actions_epinglees_par_sha(self) -> None:
        motif = re.compile(
            r"""(?m)^\s*(?:-\s*)?uses:\s*["']?([^"'\s#]+)["']?\s*(?:#.*)?$"""
        )
        actions = 0
        for workflow in self.workflows():
            for trouve in motif.finditer(lire(workflow)):
                actions += 1
                action = trouve.group(1)
                with self.subTest(workflow=workflow.name, action=action):
                    self.assertRegex(
                        action,
                        r"@[0-9a-f]{40}$",
                        "action non épinglée par un SHA de 40 hexadécimaux",
                    )
        self.assertGreater(actions, 0, "aucune action trouvée dans les workflows")

    def test_dependabot_suit_les_actions_et_les_images(self) -> None:
        self.assertTrue(self.DEPENDABOT.is_file(), ".github/dependabot.yml manquant")
        texte = lire(self.DEPENDABOT)
        for ecosysteme in ("github-actions", "docker"):
            with self.subTest(ecosysteme=ecosysteme):
                self.assertRegex(
                    texte,
                    rf"package-ecosystem:\s*[\"']?{ecosysteme}[\"']?",
                    f"écosystème {ecosysteme} absent de dependabot.yml",
                )

    def test_dependabot_ignore_mariadb_a_partir_de_11_5(self) -> None:
        texte = lire(self.DEPENDABOT)
        bloc = re.search(
            r"(?ms)^\s*-\s*package-ecosystem:\s*[\"']?docker[\"']?[^\n]*\n"
            r"(.*?)(?=^\s*-\s*package-ecosystem:|\Z)",
            texte,
        )
        if bloc is None:
            self.fail("entrée docker absente de dependabot.yml")
        contenu = bloc.group(0)
        self.assertIn("ignore:", contenu, "aucune règle ignore pour Docker")
        self.assertIn("mariadb", contenu.lower(), "MariaDB absente des dépendances ignorées")
        self.assertRegex(
            contenu,
            r">=\s*11\.5",
            "les montées MariaDB >= 11.5 doivent être ignorées (LTS 11.4)",
        )

    def test_protection_exige_le_smoke(self) -> None:
        self.assertTrue(self.PROTECTION.is_file(), "branch-protection.json manquant")
        self.assertIn(
            self.NOM_SMOKE,
            lire(self.PROTECTION),
            "le check de démarrage doit être obligatoire sur main",
        )

    def test_docker_declenche_le_smoke_sur_les_pull_requests(self) -> None:
        chemin = self.WORKFLOWS / "docker.yml"
        self.assertTrue(chemin.is_file(), "workflow docker.yml manquant")
        texte = lire(chemin)
        self.assertIn("pull_request:", texte, "docker.yml ne se déclenche pas sur les PR")
        bloc = bloc_service(texte, "smoke")
        if bloc is None:
            self.fail("job smoke absent de docker.yml")
        # La condition d'exclusion se plaçait au niveau du job (4 espaces). Les
        # étapes, elles, ont le droit de distinguer PR et envoi (login GHCR).
        conditions_job = re.findall(r"(?m)^    if:\s*(.+)$", bloc)
        for condition in conditions_job:
            with self.subTest(condition=condition.strip()):
                self.assertNotIn(
                    "github.event_name != 'pull_request'",
                    condition,
                    "le smoke est encore exclu des pull requests",
                )

    def test_smoke_garde_l_entree_standard_ouverte(self) -> None:
        texte = lire(self.WORKFLOWS / "docker.yml")
        self.assertRegex(
            texte,
            r"(?s)docker run -d --name smoke \\\n\s+--init \\\n\s+-i \\",
            "FXServer quitte quand son entrée standard est fermée : "
            "le conteneur smoke doit être lancé avec -i",
        )

    def test_chaque_job_a_timeout_permissions_et_runner_recent(self) -> None:
        for workflow in self.workflows():
            for nom, bloc in self.blocs_jobs(workflow).items():
                with self.subTest(workflow=workflow.name, job=nom):
                    self.assertRegex(
                        bloc,
                        r"(?m)^    timeout-minutes:\s*\d+\s*$",
                        "chaque job doit borner sa durée",
                    )
                    self.assertIn(
                        "runs-on: [self-hosted, Linux, X64]",
                        bloc,
                        "les jobs doivent tourner sur les runners auto-hébergés (Ubuntu 24.04)",
                    )
                    self.assertRegex(
                        bloc,
                        r"(?m)^    permissions:\s*$",
                        "chaque job doit déclarer des permissions explicites",
                    )
                    self.assertNotIn("write-all", bloc, "permissions trop larges")

    def test_qualite_execute_les_nouveaux_controles(self) -> None:
        texte = lire(self.WORKFLOWS / "qualite.yml")
        attendus = (
            "name: Qualité du dépôt",
            "luacheck server-data/resources",
            "run: actionlint",
            "run: hadolint --config .hadolint.yaml Dockerfile",
            "run: gitleaks dir",
            "run: ruff check tests/",
            "run: bash scripts/verifier.sh",
            "fetch-depth: 0",
            "run: gitleaks git",
        )
        for attendu in attendus:
            with self.subTest(controle=attendu):
                self.assertIn(attendu, texte)
        self.assertIn("  securite:", texte, "job securite séparé absent")

    def test_fxserver_version_est_epingle(self) -> None:
        chemin = RACINE / ".fxserver-version"
        self.assertTrue(chemin.is_file(), ".fxserver-version manquant")
        valeurs = cles_env(chemin)
        for cle in ("FX_VERSION", "FX_URL", "FX_SHA256"):
            with self.subTest(cle=cle):
                self.assertIn(cle, valeurs, f"{cle} absent de .fxserver-version")
                self.assertTrue(valeurs[cle], f"{cle} vide dans .fxserver-version")
        self.assertRegex(valeurs["FX_VERSION"], r"^\d+$")
        self.assertRegex(
            valeurs["FX_URL"],
            r"^https://runtime\.fivem\.net/artifacts/fivem/.+/fx\.tar\.xz$",
        )
        self.assertRegex(valeurs["FX_SHA256"], r"^[0-9a-f]{64}$")
        # L'URL pointe bien vers la version déclarée.
        self.assertIn(valeurs["FX_VERSION"], valeurs["FX_URL"])

    def test_dependabot_suit_docker_compose(self) -> None:
        texte = lire(self.DEPENDABOT)
        self.assertRegex(
            texte,
            r"package-ecosystem:\s*[\"']?docker-compose[\"']?",
            "écosystème docker-compose absent de dependabot.yml",
        )
        bloc = re.search(
            r"(?ms)^\s*-\s*package-ecosystem:\s*[\"']?docker-compose[\"']?[^\n]*\n"
            r"(.*?)(?=^\s*-\s*package-ecosystem:|\Z)",
            texte,
        )
        if bloc is None:
            self.fail("entrée docker-compose illisible")
        self.assertIn("mariadb", bloc.group(1).lower())
        self.assertRegex(bloc.group(1), r">=\s*11\.5")

    def test_docker_a_concurrence_artefact_et_test_statique(self) -> None:
        texte = lire(self.WORKFLOWS / "docker.yml")
        attendus = (
            "schedule:",
            'cron: "17 3 * * 1"',
            "group: image-${{ github.ref }}",
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            "provenance:",
            "sbom:",
            "load: ${{ github.event_name == 'pull_request' }}",
            "aquasecurity/trivy-action@",
            "severity: CRITICAL,HIGH",
            "ignore-unfixed: true",
            'exit-code: "1"',
            "LICENSE_KEY=change_moi",
            "smoke-static.log",
            "retention-days: 7",
            "if-no-files-found: ignore",
            "docker rm -f smoke",
            "docker rm -f smoke-static",
        )
        for attendu in attendus:
            with self.subTest(attendu=attendu):
                self.assertIn(attendu, texte)

        bloc = bloc_service(texte, "smoke")
        if bloc is None:
            self.fail("job smoke absent de docker.yml")
        # La construction locale sur PR ne doit dépendre ni d'un secret ni de
        # la clé : le test statique tourne toujours.
        etape = re.search(
            r"(?ms)^      - name: Construire l'image localement.*?(?=^      - name:|\Z)",
            bloc,
        )
        if etape is None:
            self.fail("étape de construction locale absente du job smoke")
        self.assertNotIn("disponible", etape.group(0))
        self.assertIn("name: Collecter les journaux", bloc)
        self.assertIn('grep -Fq -- "$CFX_LICENSE_KEY"', bloc)
        self.assertIn("if: always()", bloc, "les journaux doivent être collectés en échec")

    def test_smoke_echoue_sans_secret_hors_fork_et_dependabot(self) -> None:
        texte = lire(self.WORKFLOWS / "docker.yml")
        etape = re.search(
            r"(?ms)^      - name: Détecter la clé de licence CI.*?(?=^      - name:|\Z)",
            texte,
        )
        if etape is None:
            self.fail("étape de détection de la clé absente du job smoke")
        bloc = etape.group(0)
        self.assertIn('"$ACTEUR" = "dependabot[bot]"', bloc)
        self.assertIn('"$DEPOT_PR" != "$DEPOT"', bloc)
        self.assertIn("::error::", bloc)
        self.assertIn(
            "exit 1",
            bloc,
            "hors PR de fork ou de Dependabot, un secret absent doit faire échouer le job",
        )

    def test_nom_du_check_smoke_inchange(self) -> None:
        texte = lire(self.WORKFLOWS / "docker.yml")
        self.assertIn(f"name: {self.NOM_SMOKE}", texte)
        self.assertIn(self.NOM_SMOKE, lire(self.PROTECTION))


class DepotGit(unittest.TestCase):
    """Aucun fichier secret ne doit être suivi par Git."""

    def test_fichiers_sensibles_non_suivis(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git absent")
        try:
            sortie = subprocess.run(
                ["git", "ls-files"],
                cwd=RACINE,
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        except subprocess.CalledProcessError:  # pragma: no cover - copie sans .git
            self.skipTest("dépôt Git illisible")
        suivis = set(sortie.splitlines())
        for interdit in (
            ".env",
            "server-data/secrets.cfg",
            "server-data/resources/[gunfight]/gf_lobby/data/characters.json",
        ):
            with self.subTest(fichier=interdit):
                self.assertNotIn(interdit, suivis, "fichier sensible versionné")


if __name__ == "__main__":
    unittest.main()
