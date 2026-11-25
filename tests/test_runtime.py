"""Garde-fous du runtime Docker (aucun Démon Docker requis).

Ces tests complètent tests/test_depot.py : ils vérifient la politique de secrets,
les garde-fous des conteneurs, l'isolation réseau, l'utilisateur non privilégié
et la documentation des secrets de production. Ils lisent les fichiers du dépôt
et n'exécutent ni Docker ni Compose : ils passent sur Windows comme sur Linux.

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
COMPOSE = RACINE / "docker-compose.yml"
COMPOSE_DEV = RACINE / "docker-compose.dev.yml"
COMPOSE_PROD = RACINE / "docker-compose.prod.yml"
DOCKERFILE = RACINE / "Dockerfile"
ENTRYPOINT = RACINE / "docker" / "entrypoint.sh"
GITIGNORE = RACINE / ".gitignore"
DOCKERIGNORE = RACINE / ".dockerignore"
SECRETS_EXEMPLE = RACINE / "docker" / "secrets.exemple" / "README.md"


def lire(chemin: Path) -> str:
    # Normalise les fins de ligne : le dépôt est édité sous Windows et Linux.
    return chemin.read_text(encoding="utf-8").replace("\r\n", "\n")


def bloc_service(texte: str, nom: str) -> str:
    """Bloc YAML d'un service (les clés de service sont indentées de deux espaces)."""
    trouve = re.search(
        rf"(?ms)^  {re.escape(nom)}:\s*$.*?(?=^  [a-z][\w-]*:\s*$|^[a-z][\w-]*:\s*$|\Z)",
        texte,
    )
    if trouve is None:
        raise AssertionError(f"service {nom!r} introuvable")
    return trouve.group(0)


def section_racine(texte: str, nom: str) -> str:
    """Bloc YAML d'une section racine (`secrets:`, `networks:`, `volumes:`)."""
    trouve = re.search(
        rf"(?ms)^{re.escape(nom)}:\s*$\n(.*?)(?=^[a-z][\w-]*:\s*$|\Z)", texte
    )
    return trouve.group(1) if trouve else ""


def sous_section(bloc: str, cle: str) -> str:
    """Lignes d'une sous-section (mapping ou liste) d'un bloc de service."""
    lignes = bloc.splitlines()
    for index, ligne in enumerate(lignes):
        trouve = re.match(rf"^( +){re.escape(cle)}:\s*$", ligne)
        if trouve is None:
            continue
        indentation = len(trouve.group(1))
        recueillies: list[str] = []
        for suivante in lignes[index + 1 :]:
            if not suivante.strip():
                continue
            if len(suivante) - len(suivante.lstrip()) <= indentation:
                break
            recueillies.append(suivante)
        return "\n".join(recueillies)
    return ""


def valeur(bloc: str, cle: str) -> str:
    """Valeur scalaire d'une clé de service (`pids_limit: 512`)."""
    trouve = re.search(rf"(?m)^\s+{re.escape(cle)}:[ \t]*(\S.*?)[ \t]*$", bloc)
    return trouve.group(1) if trouve else ""


def environnement(bloc: str) -> dict[str, str]:
    """Variables d'environnement déclarées dans un bloc de service."""
    variables: dict[str, str] = {}
    for ligne in sous_section(bloc, "environment").splitlines():
        trouve = re.match(r"^\s+([A-Za-z_][\w]*):[ \t]*(.*?)[ \t]*$", ligne)
        if trouve:
            variables[trouve.group(1)] = trouve.group(2)
    return variables


def liste(bloc: str, cle: str) -> list[str]:
    """Éléments d'une liste YAML (`- valeur`) appartenant à une clé."""
    lignes = bloc.splitlines()
    for index, ligne in enumerate(lignes):
        trouve = re.match(rf"^( +){re.escape(cle)}:[ \t]*$", ligne)
        if trouve is None:
            continue
        indentation = len(trouve.group(1))
        elements: list[str] = []
        for suivante in lignes[index + 1 :]:
            if not suivante.strip():
                continue
            if len(suivante) - len(suivante.lstrip()) <= indentation:
                break
            element = re.match(r"^\s*-[ \t]*[\"']?([^\"']+?)[\"']?[ \t]*$", suivante)
            if element:
                elements.append(element.group(1))
        return elements
    return []


class SecretsHorsEnvironnement(unittest.TestCase):
    """Les secrets passent par /run/secrets, jamais par l'environnement."""

    def test_socle_sans_env_file(self) -> None:
        for chemin in (COMPOSE, COMPOSE_DEV, COMPOSE_PROD):
            self.assertNotRegex(
                lire(chemin), r"(?m)^\s*env_file:", f"env_file dans {chemin.name}"
            )

    def test_socle_ne_declare_aucun_secret(self) -> None:
        texte = lire(COMPOSE)
        fxserver = environnement(bloc_service(texte, "fxserver"))
        mariadb = environnement(bloc_service(texte, "mariadb"))
        for cle in ("LICENSE_KEY", "MARIADB_PASSWORD", "STEAM_WEB_API_KEY"):
            self.assertNotIn(cle, fxserver, f"{cle} ne doit pas être dans le socle")
        for cle in ("MARIADB_PASSWORD", "MARIADB_ROOT_PASSWORD"):
            self.assertNotIn(cle, mariadb, f"{cle} ne doit pas être dans le socle")

    def test_socle_declare_la_configuration_non_secrete(self) -> None:
        fxserver = environnement(bloc_service(lire(COMPOSE), "fxserver"))
        for cle in (
            "SERVER_NAME",
            "MAX_PLAYERS",
            "ADMIN_IDENTIFIERS",
            "MARIADB_DATABASE",
            "MARIADB_USER",
            "DB_HOST",
            "TXADMIN",
            "TXHOST_DATA_PATH",
            "TXHOST_TXA_PORT",
            "TXHOST_INTERFACE",
            "GF_SEED_MAPS",
        ):
            self.assertIn(cle, fxserver)

    def test_dev_transmet_les_secrets_explicitement(self) -> None:
        texte = lire(COMPOSE_DEV)
        fxserver = environnement(bloc_service(texte, "fxserver"))
        self.assertEqual(fxserver.get("LICENSE_KEY"), "${LICENSE_KEY:-}")
        self.assertEqual(fxserver.get("MARIADB_PASSWORD"), "${MARIADB_PASSWORD:-}")
        self.assertEqual(fxserver.get("STEAM_WEB_API_KEY"), "${STEAM_WEB_API_KEY:-}")
        mariadb = environnement(bloc_service(texte, "mariadb"))
        self.assertEqual(mariadb.get("MARIADB_ROOT_PASSWORD"), "${MARIADB_ROOT_PASSWORD:-}")
        self.assertEqual(mariadb.get("MARIADB_PASSWORD"), "${MARIADB_PASSWORD:-}")
        # Le développeur doit savoir que ces valeurs sont visibles en clair.
        self.assertIn("docker inspect", texte)

    def test_prod_declare_les_secrets_compose(self) -> None:
        section = section_racine(lire(COMPOSE_PROD), "secrets")
        for nom in ("license_key", "db_password", "db_root_password", "steam_web_api_key"):
            trouve = re.search(
                rf"(?m)^  {nom}:\s*$\n    file:\s*\$\{{SECRETS_DIR:-\./secrets\}}/{nom}\s*$",
                section,
            )
            self.assertIsNotNone(trouve, f"secret Compose {nom} mal déclaré")
        self.assertIn("SECRETS_DIR", section)

    def test_prod_neutralise_les_secrets_dans_l_environnement(self) -> None:
        texte = lire(COMPOSE_PROD)
        fxserver = environnement(bloc_service(texte, "fxserver"))
        for cle in ("LICENSE_KEY", "MARIADB_PASSWORD", "STEAM_WEB_API_KEY"):
            self.assertEqual(fxserver.get(cle), '""', f"{cle} doit être neutralisée")
        mariadb = environnement(bloc_service(texte, "mariadb"))
        self.assertEqual(mariadb.get("MARIADB_ROOT_PASSWORD"), '""')
        self.assertEqual(mariadb.get("MARIADB_PASSWORD"), '""')
        self.assertNotIn("MARIADB_PASSWORD: ${", texte)
        self.assertNotIn("MARIADB_ROOT_PASSWORD: ${", texte)

    def test_prod_mariadb_lit_les_fichiers_secrets(self) -> None:
        mariadb = environnement(bloc_service(lire(COMPOSE_PROD), "mariadb"))
        self.assertEqual(mariadb.get("MARIADB_PASSWORD_FILE"), "/run/secrets/db_password")
        self.assertEqual(
            mariadb.get("MARIADB_ROOT_PASSWORD_FILE"), "/run/secrets/db_root_password"
        )

    def test_prod_monte_les_secrets_dans_les_bons_services(self) -> None:
        texte = lire(COMPOSE_PROD)
        self.assertEqual(
            set(liste(bloc_service(texte, "fxserver"), "secrets")),
            {"license_key", "db_password", "steam_web_api_key"},
        )
        self.assertEqual(
            set(liste(bloc_service(texte, "mariadb"), "secrets")),
            {"db_root_password", "db_password"},
        )

    def test_prod_utilise_image_ref(self) -> None:
        self.assertIn("image: ${IMAGE_REF:?", lire(COMPOSE_PROD))

    def test_entrypoint_lit_run_secrets_avant_l_environnement(self) -> None:
        texte = lire(ENTRYPOINT)
        self.assertIn("/run/secrets", texte)
        for nom in ("license_key", "db_password", "steam_web_api_key"):
            self.assertIn(f"secret {nom}", texte, f"secret {nom} non lu")
        # Priorité fichier : la lecture de /run/secrets précède le repli ${...}.
        self.assertLess(texte.index('if [ -r "$_secret_fichier" ]'), texte.index("${LICENSE_KEY:-}"))
        # Fins de ligne Windows nettoyées (clé de licence et mots de passe).
        self.assertIn("tr -d '\\r\\n'", texte)
        self.assertIn("umask 077", texte)
        self.assertIn('chmod 600 "$DATA/secrets.cfg"', texte)

    def test_entrypoint_garde_le_repli_developpement(self) -> None:
        texte = lire(ENTRYPOINT)
        for repli in ("${LICENSE_KEY:-}", "${MARIADB_PASSWORD:-}", "${STEAM_WEB_API_KEY:-}"):
            self.assertIn(repli, texte)
        # Le script ne doit jamais tracer les valeurs (set -x, echo de secret),
        # et purge les variables d'environnement avant de lancer FXServer.
        self.assertNotIn("set -x", texte)
        self.assertNotIn('echo "$LICENSE_KEY"', texte)
        self.assertNotIn("echo $LICENSE_KEY", texte)
        self.assertIn("unset LICENSE_KEY STEAM_WEB_API_KEY MARIADB_PASSWORD", texte)

    def test_entrypoint_signale_la_licence_absente(self) -> None:
        texte = lire(ENTRYPOINT)
        self.assertIn("ERREUR : LICENSE_KEY est vide", texte)
        self.assertIn("change_moi", texte)
        self.assertIn("exit 1", texte)
        self.assertIn("/run/secrets/license_key", texte)


class GardeFousConteneurs(unittest.TestCase):
    """Privilèges, processus et mémoire restreints au strict nécessaire."""

    def test_fxserver_sans_privileges(self) -> None:
        bloc = bloc_service(lire(COMPOSE), "fxserver")
        self.assertEqual(liste(bloc, "security_opt"), ["no-new-privileges:true"])
        self.assertEqual(liste(bloc, "cap_drop"), ["ALL"])
        self.assertEqual(valeur(bloc, "pids_limit"), "512")
        self.assertIn("8192", sous_section(bloc, "ulimits"))
        self.assertIn("/tmp:size=64m", liste(bloc, "tmpfs"))

    def test_fxserver_memoire_limitee(self) -> None:
        self.assertIn("mem_limit: ${FXSERVER_MEMORY_LIMIT:-4g}", lire(COMPOSE))

    def test_mariadb_sans_nouveaux_privileges(self) -> None:
        bloc = bloc_service(lire(COMPOSE), "mariadb")
        self.assertEqual(liste(bloc, "security_opt"), ["no-new-privileges:true"])
        self.assertEqual(valeur(bloc, "pids_limit"), "512")
        # L'entrypoint officiel MariaDB utilise setuid/setgid/chown : cap_drop ALL
        # casserait le démarrage tant que ce n'est pas prouvé.
        self.assertEqual(liste(bloc, "cap_drop"), [])

    def test_aucun_conteneur_ne_redevient_root(self) -> None:
        for chemin in (COMPOSE, COMPOSE_DEV, COMPOSE_PROD):
            self.assertNotIn("privileged: true", lire(chemin), chemin.name)
            self.assertNotIn("USER root", lire(DOCKERFILE))


class ReseauIsole(unittest.TestCase):
    """FXServer sort, MariaDB reste sur un réseau interne."""

    def test_reseaux_declares(self) -> None:
        texte = lire(COMPOSE)
        self.assertIn("frontend:", section_racine(texte, "networks"))
        self.assertIn("internal: true", section_racine(texte, "networks"))

    def test_repartition_des_reseaux(self) -> None:
        texte = lire(COMPOSE)
        fxserver = set(liste(bloc_service(texte, "fxserver"), "networks"))
        mariadb = set(liste(bloc_service(texte, "mariadb"), "networks"))
        self.assertEqual(fxserver, {"frontend", "backend"})
        self.assertEqual(mariadb, {"backend"})

    def test_mariadb_sans_port_publie(self) -> None:
        bloc = bloc_service(lire(COMPOSE), "mariadb")
        self.assertEqual(liste(bloc, "ports"), [])

    def test_port_txadmin_local_uniquement(self) -> None:
        ports = liste(bloc_service(lire(COMPOSE), "fxserver"), "ports")
        self.assertIn("127.0.0.1:40120:40120/tcp", ports)
        self.assertNotIn("40120:40120/tcp", ports)


class UtilisateurNonRoot(unittest.TestCase):
    """L'image tourne avec fivem (10001), le dev reste root pour le bind mount."""

    def test_utilisateur_fivem_cree(self) -> None:
        texte = lire(DOCKERFILE)
        self.assertIn("groupadd --gid 10001 fivem", texte)
        self.assertIn("useradd --uid 10001 --gid 10001", texte)
        self.assertIn("USER 10001:10001", texte)

    def test_utilisateur_active_en_dernier(self) -> None:
        texte = lire(DOCKERFILE)
        index_user = texte.rindex("USER 10001:10001")
        for apres in ("COPY server-data/ /opt/fivem/defaults/", "chown -R 10001:10001 /opt/fivem"):
            self.assertLess(texte.index(apres), index_user, f"{apres} doit précéder USER")

    def test_dossiers_inscriptibles_par_fivem(self) -> None:
        texte = lire(DOCKERFILE)
        self.assertIn("chown -R 10001:10001 /opt/fivem", texte)
        self.assertIn("mkdir -p /opt/fivem/txData", texte)
        self.assertIn("ENV HOME=/opt/fivem", texte)

    def test_curl_present_pour_le_healthcheck(self) -> None:
        self.assertIn("curl", lire(DOCKERFILE))
        self.assertIn("healthcheck:", lire(COMPOSE))

    def test_dev_reste_root_pour_le_bind_mount_windows(self) -> None:
        texte = lire(COMPOSE_DEV)
        self.assertIn('user: "0:0"', texte)
        self.assertIn("bind mount", texte)
        self.assertIn("10001", texte)


class FichiersIgnores(unittest.TestCase):
    """Les secrets ne peuvent être ni commités ni embarqués dans l'image."""

    def test_gitignore(self) -> None:
        lignes = {ligne.strip() for ligne in lire(GITIGNORE).splitlines()}
        for attendu in (".env", "secrets/", "server-data/secrets.cfg", "server-data/cache/"):
            self.assertIn(attendu, lignes)

    def test_dockerignore(self) -> None:
        lignes = {ligne.strip() for ligne in lire(DOCKERIGNORE).splitlines()}
        for attendu in (".env", "secrets/", "server-data/secrets.cfg", "server-data/cache/"):
            self.assertIn(attendu, lignes)


class DocumentationSecrets(unittest.TestCase):
    """Le modèle de secrets de production reste documenté et versionné."""

    def test_modele_present(self) -> None:
        self.assertTrue(SECRETS_EXEMPLE.is_file())

    def test_modele_decrit_les_fichiers(self) -> None:
        texte = lire(SECRETS_EXEMPLE)
        for nom in ("license_key", "db_password", "db_root_password", "steam_web_api_key"):
            self.assertIn(nom, texte)
        self.assertIn("chmod 600", texte)
        self.assertIn("SECRETS_DIR", texte)
        self.assertIn("CRLF", texte)


class VersionDuBuild(unittest.TestCase):
    """Le badge du lobby affiche le sha du commit construit par la CI.

    Chaîne : .github/workflows/docker.yml (sha court) -> argument BUILD_SHA ->
    variable GF_BUILD_SHA de l'image -> convar gf_build_sha dans secrets.cfg ->
    `build` de l'état du lobby -> interface. Chaque maillon est vérifié : si un
    seul saute, le badge affiche une version qui n'est plus celle du code.
    """

    NUI = RACINE / "server-data" / "resources" / "[gunfight]" / "gf_lobby" / "html"
    SERVEUR = RACINE / "server-data" / "resources" / "[gunfight]" / "gf_lobby" / "server.lua"
    WORKFLOW = RACINE / ".github" / "workflows" / "docker.yml"
    CALCUL = (
        "echo \"BUILD_SHA=$(printf '%s' '${{ github.sha }}' | cut -c1-7)\""
        ' >> "$GITHUB_ENV"'
    )

    def test_dockerfile_declare_et_exporte_l_argument(self) -> None:
        texte = lire(DOCKERFILE)
        self.assertRegex(texte, r"(?m)^ARG BUILD_SHA=dev$", "argument BUILD_SHA absent")
        self.assertIn("ENV GF_BUILD_SHA=${BUILD_SHA}", texte, "GF_BUILD_SHA non exportée")
        self.assertLess(
            texte.index("ARG BUILD_SHA"),
            texte.index("GF_BUILD_SHA"),
            "l'argument doit précéder son export",
        )

    def test_entrypoint_publie_la_convar(self) -> None:
        texte = lire(ENTRYPOINT)
        self.assertIn("${GF_BUILD_SHA:-}", texte, "l'entrypoint ignore GF_BUILD_SHA")
        self.assertIn(
            'echo "set gf_build_sha \\"$BUILD_SHA\\""', texte, "convar gf_build_sha non écrite"
        )
        # La valeur vient d'un argument de build : elle est nettoyée avant
        # d'atterrir dans secrets.cfg, qui est lu par le serveur.
        self.assertIn("tr -cd '0-9a-fA-F'", texte, "le sha n'est pas nettoyé")
        self.assertIn("BUILD_SHA=dev", texte, "repli « dev » absent")

    def test_serveur_lit_la_convar(self) -> None:
        texte = lire(self.SERVEUR)
        self.assertIn("GetConvar('gf_build_sha'", texte, "la convar n'est pas lue")
        self.assertIn("build = buildSha(),", texte, "le sha n'entre pas dans l'état du lobby")

    def test_interface_naffiche_plus_de_sha_en_dur(self) -> None:
        for nom in ("index.html", "js/app.js"):
            texte = lire(self.NUI / nom)
            with self.subTest(fichier=nom):
                self.assertNotIn("7259e64", texte, "ancien sha toujours en dur")
                self.assertNotIn("b8b4a5c", texte, "ancien sha toujours en dur")
        app = lire(self.NUI / "js" / "app.js")
        self.assertIn("var BUILD = 'dev';", app, "repli « dev » absent de l'interface")
        self.assertIn("applyBuild(next.build)", app, "le sha reçu n'est pas appliqué au badge")

    def test_workflow_transmet_le_sha_aux_deux_builds(self) -> None:
        texte = lire(self.WORKFLOW)
        self.assertEqual(
            texte.count(self.CALCUL), 2, "le sha doit être calculé dans les deux jobs"
        )
        self.assertIn("BUILD_SHA=${{ env.BUILD_SHA }}", texte, "job image sans BUILD_SHA")
        self.assertIn(
            '--build-arg "BUILD_SHA=$BUILD_SHA"', texte, "job smoke sans BUILD_SHA"
        )


if __name__ == "__main__":
    unittest.main()
