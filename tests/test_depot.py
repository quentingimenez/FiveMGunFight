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
RESSOURCES_GUNFIGHT = ("gf_core", "gf_ui", "gf_maps", "gf_attack", "gf_redzone", "gf_lobby", "gf_stats", "gf_menu", "gf_vehicles", "gf_thumbs", "gf_db", "gf_journal", "gf_weapons")
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


def scripts_client(manifeste: Path) -> set[str]:
    """Scripts Lua exécutés par le client (client_script(s) et shared_script(s))."""
    texte = lire(manifeste)
    chemins: set[str] = set()
    for mot in ("client_scripts", "client_script", "shared_scripts", "shared_script"):
        motif = rf"\b{mot}\b\s*(\{{[^}}]*\}}|'[^']*'|\"[^\"]*\")"
        for trouve in re.finditer(motif, texte):
            for simple, double in re.findall(r"'([^']+)'|\"([^\"]+)\"", trouve.group(1)):
                chemins.add(simple or double)
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
                # Un chemin préfixé par '@' désigne un script d'une autre
                # ressource FiveM (ex. '@oxmysql/lib/MySQL.lua') : il est résolu
                # par FXServer au chargement et n'existe donc pas dans le dossier
                # de cette ressource. On ne le vérifie pas comme un fichier local.
                if chemin.startswith("@"):
                    continue
                with self.subTest(manifeste=str(manifeste.relative_to(RACINE)), chemin=chemin):
                    self.assertTrue(
                        (manifeste.parent / chemin).is_file(),
                        f"fichier déclaré introuvable : {chemin}",
                    )

    def test_images_des_ressources_sont_declarees(self) -> None:
        # Le client ne reçoit que les fichiers listés : une image qu'il charge
        # lui-même (NUI, CreateRuntimeTextureFromImage) et absente de `files`
        # est introuvable, et CreateRuntimeTextureFromImage échoue sans message
        # clair. Les images que seul le serveur lit (gf_thumbs les envoie en
        # base64) ne sont citées par aucun fichier client et sont ignorées.
        extensions = {".png", ".jpg", ".jpeg", ".webp", ".gif"}
        for manifeste in manifestes():
            declares = chemins_declares(manifeste)
            sources_client = "\n".join(
                lire(source) for source in sorted(manifeste.parent.rglob("*"))
                if source.is_file() and "cache" not in source.parts and (
                    source.suffix in {".html", ".js", ".css"}
                    or source.relative_to(manifeste.parent).as_posix() in scripts_client(manifeste)
                )
            )
            for image in sorted(manifeste.parent.rglob("*")):
                if image.suffix.lower() not in extensions or "cache" in image.parts:
                    continue
                if image.name not in sources_client:
                    continue
                chemin = image.relative_to(manifeste.parent).as_posix()
                with self.subTest(manifeste=str(manifeste.relative_to(RACINE)), image=chemin):
                    self.assertIn(chemin, declares, f"image non déclarée dans files : {chemin}")

    def test_textures_runtime_recoivent_un_handle_de_txd(self) -> None:
        # CreateRuntimeTextureFrom* attend le handle renvoyé par
        # CreateRuntimeTxd. Un nom de dictionnaire en dur provoque
        # « invalid handle » en jeu (erreur déjà rencontrée sur gf_lobby).
        appel_avec_nom = re.compile(r"CreateRuntimeTextureFrom\w*\s*,?\s*\(?\s*['\"]")
        for script in sorted(RESSOURCES.glob("*/gf_*/**/*.lua")):
            for numero, ligne in enumerate(lire(script).splitlines(), start=1):
                with self.subTest(script=str(script.relative_to(RACINE)), ligne=numero):
                    self.assertIsNone(
                        appel_avec_nom.search(ligne),
                        f"txd passé par son nom au lieu du handle de CreateRuntimeTxd : {ligne.strip()}",
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
            r"(?m)^FROM\s+\S+@sha256:[0-9a-f]{64}(?:\s+AS\s+\w+)?\s*$",
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

    def test_entrypoint_complete_les_donnees_sans_ecraser(self) -> None:
        texte = lire(self.ENTRYPOINT)
        self.assertIn("GF_SEED_DATA", texte)
        self.assertIn("cp -Rn", texte, "le complément depuis l'image ne doit pas écraser")
        for dossier in ("gf_thumbs/thumbs", "gf_vehicles/custom"):
            with self.subTest(dossier=dossier):
                self.assertIn(dossier, texte)


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
            ("thumbs", "gunfight-prod-thumbs"),
            ("vehicles", "gunfight-prod-vehicles"),
        ):
            with self.subTest(volume=volume):
                self.assertEqual(prod.get(volume), nom, "volume de production mal nommé")
                self.assertNotIn(nom, dev, "volume de production présent dans le dev")
                self.assertNotIn(nom, socle, "volume de production présent dans le socle")

    def test_prod_persiste_les_donnees_creees_en_jeu(self) -> None:
        # Photos des menus (/thumbs) et véhicule de base + customs (/customveh) :
        # sans volume, une mise à jour de l'image les effacerait.
        bloc = self.bloc(self.PROD, "fxserver")
        for montage in (
            "thumbs:/opt/fivem/server-data/resources/[gunfight]/gf_thumbs/thumbs",
            "vehicles:/opt/fivem/server-data/resources/[gunfight]/gf_vehicles/custom",
        ):
            with self.subTest(montage=montage):
                self.assertIn(montage, bloc, "donnée de jeu non persistée en production")
        self.assertRegex(bloc, r'GF_SEED_DATA: *"?true"?', "GF_SEED_DATA doit valoir true")

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
        texte = lire(
            RESSOURCES / "[gunfight]" / "gf_db" / "migrations" / "0001_gf_stats_players.sql"
        )
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


class Migrations(unittest.TestCase):
    """Les migrations de gf_db restent numérotées, déclarées et ordonnées.

    Une migration non déclarée ne sera jamais appliquée ; une somme modifiée
    empêche gf_db de démarrer. Ces contrôles gardent les fichiers SQL et leur
    registre synchronisés, et garantissent que le schéma est prêt avant
    gf_stats.
    """

    BASE = RESSOURCES / "[gunfight]" / "gf_db"
    REGISTRE = BASE / "migrations.lua"
    CONFIG = RACINE / "server-data" / "server.cfg"

    def migrations_fichiers(self) -> list[Path]:
        """Fichiers de migration présents, triés par nom."""
        return sorted(self.BASE.glob("migrations/*.sql"))

    def test_fichiers_numérotés_sans_trou_et_noms_valides(self) -> None:
        fichiers = self.migrations_fichiers()
        self.assertTrue(fichiers, "aucun fichier de migration trouvé")
        versions: list[int] = []
        for fichier in fichiers:
            with self.subTest(fichier=fichier.name):
                self.assertRegex(
                    fichier.name,
                    r"^\d{4}_[a-z0-9_]+\.sql$",
                    "nom de migration invalide (attendu NNNN_nom.sql en minuscules)",
                )
                versions.append(int(fichier.name[:4]))
        self.assertEqual(
            versions, list(range(1, len(versions) + 1)),
            "les migrations doivent être numérotées 0001, 0002… sans trou",
        )

    def test_chaque_migration_est_déclarée_dans_le_registre(self) -> None:
        registre = lire(self.REGISTRE)
        entrees = re.findall(r"\{[^{}]*\}", registre)
        for fichier in self.migrations_fichiers():
            version = int(fichier.name[:4])
            chemin = f"migrations/{fichier.name}"
            with self.subTest(fichier=fichier.name):
                declaree = [
                    entree for entree in entrees
                    if chemin in entree
                    and re.search(rf"\bversion\s*=\s*0*{version}\b", entree)
                ]
                self.assertTrue(
                    declaree,
                    "migration absente de migrations.lua ou version différente "
                    f"(attendu : version {version:04d}, fichier {chemin})",
                )

    def test_gf_db_démarre_avant_gf_stats(self) -> None:
        texte = lire(self.CONFIG)
        db = texte.find("ensure gf_db")
        stats = texte.find("ensure gf_stats")
        self.assertGreaterEqual(db, 0, "ensure gf_db absent de server.cfg")
        self.assertGreater(stats, db, "gf_db doit démarrer avant gf_stats")


class VehiculesDeclares(unittest.TestCase):
    """Chaque véhicule de Config.Vehicles est complet et déclaré.

    Garde-fou de scripts/ajouter_vehicule.py (voir docs/ajouter-un-modele.md) :
    un véhicule listé dans le menu sans modèle 3D ou sans réglages ne
    s'afficherait pas en jeu.
    """

    BASE = RESSOURCES / "[gunfight]" / "gf_vehicles"

    @classmethod
    def setUpClass(cls) -> None:
        config = lire(cls.BASE / "config.lua")
        bloc = config[config.index("Config.Vehicles = {"):]
        bloc = bloc[: bloc.index("\n}")]
        cls.modeles = re.findall(r"model\s*=\s*'([^']+)'", bloc)
        cls.manifeste = lire(cls.BASE / "fxmanifest.lua")
        cls.defaut = re.search(r"Config\.DefaultModel\s*=\s*'([^']+)'", config).group(1)

    def test_au_moins_un_vehicule_et_defaut_connu(self) -> None:
        self.assertTrue(self.modeles, "Config.Vehicles est vide")
        self.assertEqual(len(self.modeles), len(set(self.modeles)), "modèle listé deux fois")
        self.assertIn(self.defaut, self.modeles, "Config.DefaultModel absent de Config.Vehicles")

    def test_chaque_vehicule_a_son_modele_3d(self) -> None:
        for modele in self.modeles:
            with self.subTest(modele=modele):
                self.assertTrue((self.BASE / "stream" / f"{modele}.yft").is_file(), "stream/<modèle>.yft manquant")
                self.assertTrue((self.BASE / "stream" / f"{modele}.ytd").is_file(), "stream/<modèle>.ytd manquant")

    def test_chaque_vehicule_a_ses_reglages_declares(self) -> None:
        for modele in self.modeles:
            with self.subTest(modele=modele):
                meta = self.BASE / "data" / modele / "vehicles.meta"
                self.assertTrue(meta.is_file(), "data/<modèle>/vehicles.meta manquant")
                self.assertIn(f"<modelName>{modele}</modelName>", lire(meta).replace(" ", ""))
                for fichier in sorted((self.BASE / "data" / modele).glob("*.meta")):
                    self.assertIn(f"'data/{modele}/{fichier.name}'", self.manifeste,
                                  f"{fichier.name} n'est pas déclaré dans files {{}}")

    def test_pas_de_lien_publicitaire_dans_les_noms(self) -> None:
        for meta in sorted((self.BASE / "data").glob("*/vehicles.meta")):
            texte = lire(meta)
            for balise in ("gameName", "vehicleMakeName"):
                with self.subTest(fichier=meta.parent.name, balise=balise):
                    for valeur in re.findall(rf"<{balise}>([^<]*)</{balise}>", texte):
                        self.assertNotRegex(valeur, r"(?i)https?://|discord|\.gg/")


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
        "docs/regles-de-code.md",
        "docs/chantiers-techniques.md",
        "docs/methode/README.md",
        "docs/methode/fiche-impact.md",
        "docs/methode/strategie-de-test.md",
        "docs/methode/architecture-cible.md",
        "docs/methode/orchestration-agents.md",
        "docs/adr/README.md",
        ".github/pull_request_template.md",
        ".github/CODEOWNERS",
    )

    def test_documents_presents_et_remplis(self) -> None:
        for document in self.DOCUMENTS:
            with self.subTest(document=document):
                chemin = RACINE / document
                self.assertTrue(chemin.is_file(), "document manquant")
                self.assertGreater(len(lire(chemin).strip()), 200, "document vide ou presque")

    def test_regles_de_code_referencees_et_citees_juste(self) -> None:
        # Les règles ne s'appliquent que si CONTRIBUTING.md (la référence pour
        # le fond) y renvoie, et un chantier ne peut citer qu'une règle définie.
        self.assertIn("docs/regles-de-code.md", lire(RACINE / "CONTRIBUTING.md"))
        index = lire(RACINE / "docs" / "README.md")
        for document in ("regles-de-code.md", "chantiers-techniques.md"):
            with self.subTest(index=document):
                self.assertIn(f"]({document})", index, "document absent de docs/README.md")
        regles = lire(RACINE / "docs" / "regles-de-code.md")
        chantiers = lire(RACINE / "docs" / "chantiers-techniques.md")
        citees = sorted(set(re.findall(r"\b[SAPNDUEV]\d+\b", chantiers)))
        self.assertTrue(citees, "aucun chantier ne cite de règle")
        for regle in citees:
            with self.subTest(regle=regle):
                self.assertRegex(regles, rf"\*\*{regle} — ", "règle citée mais non définie")

    def test_claude_md_importe_agents_md_et_impose_la_fusion(self) -> None:
        # Claude Code ne lit que CLAUDE.md : sans import explicite, il ignore
        # le déroulé d'AGENTS.md et laisse des PR vertes sans les fusionner.
        chemin = RACINE / "CLAUDE.md"
        self.assertTrue(chemin.is_file(), "CLAUDE.md manquant")
        texte = lire(chemin)
        self.assertRegex(texte, r"(?m)^@AGENTS\.md\s*$", "CLAUDE.md doit importer AGENTS.md")
        self.assertIn("gh pr merge", texte, "CLAUDE.md doit rappeler la fusion par l'agent")
        self.assertIn("gh pr checks", texte, "CLAUDE.md doit imposer le suivi de la CI jusqu'au vert")

    def test_gemini_md_importe_agents_md(self) -> None:
        # Gemini CLI lit GEMINI.md, pas AGENTS.md.
        chemin = RACINE / "GEMINI.md"
        self.assertTrue(chemin.is_file(), "GEMINI.md manquant")
        self.assertRegex(lire(chemin), r"(?m)^@AGENTS\.md\s*$", "GEMINI.md doit importer AGENTS.md")

    def test_agents_md_coherent_pour_tout_agent(self) -> None:
        texte = lire(RACINE / "AGENTS.md")
        interdits = texte.split("## 5. Interdits", 1)[1].split("\n## ", 1)[0]
        # § 4.7 impose --force-with-lease après un rebase : les interdits ne
        # doivent pas le défendre en même temps.
        self.assertNotIn(
            "`git push --force` / `--force-with-lease`",
            interdits,
            "force-push avec bail à la fois imposé et interdit",
        )
        self.assertRegex(
            interdits,
            r"seul `--force-with-lease` sur la branche de la\s+PR est permis",
            "les interdits doivent réserver le force-push avec bail à la branche de la PR",
        )
        self.assertNotIn("(privé)", texte, "le dépôt est public : contexte périmé")

    def test_fusion_et_suivi_de_main_par_le_script(self) -> None:
        texte = lire(RACINE / "AGENTS.md")
        self.assertIn("scripts/fusionner-pr.sh", texte, "AGENTS.md doit imposer le script de fusion")
        terminee = texte.split("## 2.", 1)[1].split("\n## ", 1)[0]
        self.assertRegex(
            " ".join(terminee.split()),
            r"\*\*CI de `main`\*\* est \*\*verte\*\* sur le commit de fusion",
            "session terminée = CI de main verte",
        )
        self.assertIn("scripts/fusionner-pr.sh", lire(RACINE / "CLAUDE.md"))

    def test_langues_du_projet_fixees_pour_tout_agent(self) -> None:
        # Documentation et descriptions de PR en français, commits en anglais.
        for document in ("AGENTS.md", "CONTRIBUTING.md"):
            with self.subTest(document=document):
                texte = " ".join(lire(RACINE / document).split())
                self.assertRegex(texte, r"messages de commit sont \*\*en anglais\*\*")
                self.assertRegex(texte, r"description de la PR sont rédigées \*\*en français\*\*")

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


class Methode(unittest.TestCase):
    """La méthode de développement reste indexée et imposée à tous les agents."""

    def test_documents_de_methode_indexes(self) -> None:
        dossier = RACINE / "docs" / "methode"
        fichiers = sorted(dossier.glob("*.md"))
        self.assertTrue(fichiers, "aucun document de méthode trouvé")
        index = lire(RACINE / "docs" / "README.md")
        for fichier in fichiers:
            with self.subTest(fichier=fichier.name):
                self.assertIn(
                    f"](methode/{fichier.name})",
                    index,
                    "document de méthode absent de l'index docs/README.md",
                )

    def test_index_des_adr_complet_et_sans_trou(self) -> None:
        dossier = RACINE / "docs" / "adr"
        fichiers = sorted(
            fichier for fichier in dossier.glob("*.md")
            if re.fullmatch(r"[0-9]{4}-.+[.]md", fichier.name)
        )
        self.assertTrue(fichiers, "aucun ADR numéroté trouvé")
        index = lire(dossier / "README.md")
        numeros: list[int] = []
        for fichier in fichiers:
            with self.subTest(fichier=fichier.name):
                self.assertIn(
                    f"]({fichier.name})", index, "ADR absent de l'index docs/adr/README.md"
                )
                numeros.append(int(fichier.name[:4]))
        self.assertEqual(
            sorted(numeros),
            list(range(1, len(numeros) + 1)),
            "les ADR doivent être numérotés 0001, 0002… sans trou",
        )

    def test_agents_md_impose_la_methode(self) -> None:
        texte = lire(RACINE / "AGENTS.md")
        for attendu in (
            "### 4.0 Cadrer et situer",
            "docs/methode/fiche-impact.md",
            "docs/methode/strategie-de-test.md",
            "docs/methode/README.md",
        ):
            with self.subTest(attendu=attendu):
                self.assertIn(attendu, texte, "méthode absente de AGENTS.md")

    def test_modele_de_pr_suit_la_methode(self) -> None:
        texte = lire(RACINE / ".github" / "pull_request_template.md")
        for titre in (
            "## Fiche d'impact",
            "## Tests et preuve",
            "## Risques et retour arrière",
            "## Cause racine",
        ):
            with self.subTest(titre=titre):
                self.assertIn(titre, texte, "section absente du modèle de pull request")

    def test_categories_de_cause_racine_definies(self) -> None:
        modele = lire(RACINE / ".github" / "pull_request_template.md")
        methode = lire(RACINE / "docs" / "methode" / "README.md")
        for categorie in (
            "exigence",
            "effet-de-bord",
            "contrat",
            "plateforme",
            "etat",
            "calques-nui",
            "asset",
        ):
            with self.subTest(categorie=categorie):
                self.assertIn(categorie, modele, "catégorie absente du modèle de pull request")
                self.assertIn(
                    chr(96) + categorie + chr(96),
                    methode,
                    "catégorie non définie dans docs/methode/README.md",
                )

    def test_niveaux_de_test_distincts_des_regles(self) -> None:
        regles = lire(RACINE / "docs" / "regles-de-code.md")
        self.assertIsNone(
            re.search(r"[*][*]T[0-9]+ — ", regles),
            "un niveau de test est défini comme règle de code",
        )
        strategie = lire(RACINE / "docs" / "methode" / "strategie-de-test.md")
        for niveau in ("**T0 statique**", "**T6 humain**"):
            with self.subTest(niveau=niveau):
                self.assertIn(niveau, strategie, "niveau de test absent de la stratégie")


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
                    self.assertRegex(
                        bloc,
                        r"(?m)^    runs-on: ubuntu-24\.04\s*$",
                        "les jobs doivent tourner sur les runners GitHub Ubuntu 24.04",
                    )
                    self.assertRegex(
                        bloc,
                        r"(?m)^    permissions:\s*$",
                        "chaque job doit déclarer des permissions explicites",
                    )
                    self.assertNotIn("write-all", bloc, "permissions trop larges")

    def test_alerte_main_ouvre_une_issue_sur_echec(self) -> None:
        # Filet si personne ne suit la CI de main après une fusion.
        chemin = self.WORKFLOWS / "alerte-main.yml"
        self.assertTrue(chemin.is_file(), "workflow alerte-main.yml manquant")
        texte = lire(chemin)
        self.assertRegex(texte, r"(?m)^  workflow_run:\s*$")
        self.assertRegex(texte, r'workflows: \["Qualité", "Docker"\]')
        self.assertRegex(texte, r"branches: \[main\]")
        self.assertIn("workflow_run.conclusion", texte)
        self.assertIn("issues: write", texte)
        self.assertIn("gh issue create", texte)
        # Le titre du commit est une donnée externe : jamais interpolé dans run.
        blocs = re.findall(r"(?ms)^        run: \|\n(.*?)(?=^      - |\Z)", texte)
        self.assertTrue(blocs, "aucun script run: | trouvé")
        for bloc in blocs:
            self.assertNotIn("${{", bloc, "expression GitHub interpolée dans un script")

    def test_qualite_lance_la_commande_unique(self) -> None:
        texte = lire(self.WORKFLOWS / "qualite.yml")
        bloc = bloc_service(texte, "qualite")
        if bloc is None:
            self.fail("job qualite absent de qualite.yml")
        self.assertIn("name: Qualité du dépôt", bloc)
        self.assertIn("run: bash scripts/verifier-docker.sh", bloc)
        self.assertIn("timeout-minutes: 20", bloc)
        self.assertNotIn(
            "apt-get install",
            bloc,
            "le job qualite ne doit plus installer d'outils sur le runner",
        )
        self.assertNotIn(
            "setup-node",
            bloc,
            "Node doit venir de l'image de vérification, pas du runner",
        )
        # Le job séparé garde tout l'historique pour gitleaks git.
        self.assertIn("  securite:", texte, "job securite séparé absent")
        self.assertIn("fetch-depth: 0", texte)
        self.assertIn("run: gitleaks git", texte)

    def test_qualite_n_annule_que_sur_pull_request(self) -> None:
        # Sur main, une annulation laisserait le commit de fusion sans check
        # requis et sans issue d'alerte (conclusion « cancelled » non surveillée).
        texte = lire(self.WORKFLOWS / "qualite.yml")
        self.assertIn(
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            texte,
            "qualite.yml doit annuler seulement les runs de pull request",
        )
        self.assertNotIn(
            "cancel-in-progress: true",
            texte,
            "un run de main ne doit jamais être annulé",
        )

    def test_qualite_met_l_image_en_cache(self) -> None:
        # Sans cache, l'apt-get de l'image dépend du débit d'archive.ubuntu.com
        # (jusqu'à 10 minutes) ; le scope distinct protège le cache de docker.yml.
        bloc = bloc_service(lire(self.WORKFLOWS / "qualite.yml"), "qualite")
        if bloc is None:
            self.fail("job qualite absent de qualite.yml")
        self.assertIn("cache-from: type=gha,scope=verifier", bloc)
        self.assertIn("cache-to: type=gha,scope=verifier,mode=max", bloc)
        self.assertIn("APT_MIRROR=http://azure.archive.ubuntu.com/ubuntu", bloc)
        self.assertIn(
            "APT_SECURITY_MIRROR=http://azure.archive.ubuntu.com/ubuntu", bloc
        )
        self.assertIn("GF_VERIFIER_IMAGE: gunfight-verifier:ci", bloc)
        self.assertIn("tags: gunfight-verifier:ci", bloc)
        image = lire(RACINE / "docker" / "verifier" / "Dockerfile")
        self.assertIn("ARG APT_MIRROR=http://archive.ubuntu.com/ubuntu", image)
        self.assertIn(
            "ARG APT_SECURITY_MIRROR=http://security.ubuntu.com/ubuntu", image
        )
        self.assertIn('Acquire::Retries "3"', image)

    def test_image_de_verification_est_epinglee(self) -> None:
        chemin = RACINE / "docker" / "verifier" / "Dockerfile"
        self.assertTrue(chemin.is_file(), "docker/verifier/Dockerfile manquant")
        texte = lire(chemin)
        self.assertRegex(
            texte,
            r"(?m)^FROM\s+ubuntu:24\.04@sha256:[0-9a-f]{64}\s*$",
            "l'image de vérification doit être épinglée par digest",
        )
        for outil in (
            "actionlint",
            "hadolint",
            "gitleaks",
            "ruff",
            "node",
            "docker",
            "docker-compose",
        ):
            with self.subTest(outil=outil):
                self.assertIn(outil, texte)
        self.assertGreaterEqual(
            texte.count("| sha256sum -c -"),
            7,
            "chacun des 7 binaires doit être vérifié par son empreinte SHA256",
        )
        for paquet in ("luacheck", "shellcheck", "lua5.4"):
            with self.subTest(paquet=paquet):
                self.assertIn(paquet, texte)

    def test_gitleaks_est_aligne_entre_ci_et_image(self) -> None:
        workflow = lire(self.WORKFLOWS / "qualite.yml")
        image = lire(RACINE / "docker" / "verifier" / "Dockerfile")
        version_ci = re.search(r'GITLEAKS_VERSION:\s*"([^"]+)"', workflow)
        sha_ci = re.search(r'GITLEAKS_SHA256:\s*"([^"]+)"', workflow)
        version_image = re.search(r"ARG GITLEAKS_VERSION=(\S+)", image)
        sha_image = re.search(r"ARG GITLEAKS_SHA256=(\S+)", image)
        for nom, trouve in (
            ("version gitleaks CI", version_ci),
            ("SHA256 gitleaks CI", sha_ci),
            ("version gitleaks image", version_image),
            ("SHA256 gitleaks image", sha_image),
        ):
            if trouve is None:
                self.fail(f"{nom} illisible")
        self.assertEqual(version_ci.group(1), version_image.group(1))
        self.assertEqual(sha_ci.group(1), sha_image.group(1))

    def test_verifier_sh_est_strict(self) -> None:
        texte = lire(RACINE / "scripts" / "verifier.sh")
        self.assertNotIn('ignore "', texte, "plus aucun outil ne doit être ignoré")
        self.assertIn("GF_OUTILS_OBLIGATOIRES=1", texte)
        self.assertIn("unittest discover", texte)

    def test_verifier_sh_analyse_l_arbre_suivi(self) -> None:
        texte = lire(RACINE / "scripts" / "verifier.sh")
        etape = texte.split("# --- 8. Secrets dans l'arbre (gitleaks)", 1)
        self.assertEqual(len(etape), 2, "étape gitleaks introuvable")
        bloc = etape[1].split("# --- 9.", 1)[0]
        self.assertIn(
            "scripts/arbre-suivi.sh",
            bloc,
            "l'étape gitleaks doit analyser une copie des fichiers vus par Git",
        )

    def test_dependabot_suit_l_image_de_verification(self) -> None:
        texte = lire(self.DEPENDABOT)
        self.assertIn('directory: "/docker/verifier"', texte)

    def test_dependabot_garde_l_image_de_verification_sur_ubuntu_24_04(self) -> None:
        # Le runner CI et l'image de vérification partagent le même système :
        # seules les montées majeures et mineures d'ubuntu sont exclues, le
        # digest de 24.04 continue d'être mis à jour.
        entrees = re.findall(
            r"(?ms)^\s*-\s*package-ecosystem:.*?(?=^\s*-\s*package-ecosystem:|\Z)",
            lire(self.DEPENDABOT),
        )
        verificateur = [
            entree
            for entree in entrees
            if 'directory: "/docker/verifier"' in entree
        ]
        self.assertEqual(
            len(verificateur),
            1,
            'une seule entrée avec directory: "/docker/verifier" est attendue',
        )
        entree = verificateur[0]
        self.assertIn(
            'dependency-name: "ubuntu"',
            entree,
            "l'image de vérification doit rester sur Ubuntu 24.04 : "
            "exclure explicitement ubuntu dans cette entrée",
        )
        for type_maj in (
            "version-update:semver-major",
            "version-update:semver-minor",
        ):
            with self.subTest(type=type_maj):
                self.assertIn(
                    type_maj,
                    entree,
                    "l'image de vérification doit rester sur Ubuntu 24.04 : "
                    "les montées majeures et mineures d'ubuntu doivent être "
                    "ignorées, seul le digest de 24.04 continue d'être mis à jour",
                )

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

    def test_trivy_scanne_aussi_les_publications(self) -> None:
        """Le scan ne doit pas se limiter aux pull requests.

        La relance hebdomadaire n'a de sens que si elle scanne l'image publiée :
        c'est la seule veille des CVE qui reste quand le dépôt ne change pas.
        """
        texte = lire(self.WORKFLOWS / "docker.yml")
        etape = re.search(
            r"(?ms)^      - name: Scanner l'image \(Trivy\).*?(?=^      - name:|\Z)",
            texte,
        )
        if etape is None:
            self.fail("étape Trivy absente de docker.yml")
        self.assertNotIn("if:", etape.group(0))
        self.assertIn(
            "image-ref: ${{ env.IMAGE_LC }}:ci-${{ github.sha }}", etape.group(0)
        )

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

    def test_smoke_sans_annuler_les_autres_refs(self) -> None:
        # GitHub ne garde qu'un run en attente par groupe de concurrence : un
        # groupe global annulait le smoke des autres PR (et même de main). Le
        # groupe ne regroupe donc que les runs d'une même référence.
        bloc = bloc_service(lire(self.WORKFLOWS / "docker.yml"), "smoke")
        if bloc is None:
            self.fail("job smoke absent de docker.yml")
        groupe = re.search(r"(?m)^      group:\s*(.+?)\s*$", bloc)
        if groupe is None:
            self.fail("concurrence absente du job smoke")
        self.assertIn(
            "github.ref",
            groupe.group(1),
            "un groupe partagé entre références annule les smoke en attente des autres PR",
        )
        self.assertIn(
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            bloc,
            "seuls les runs obsolètes d'une même PR peuvent être annulés",
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
