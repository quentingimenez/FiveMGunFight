"""Tests du lot exploitation : scripts, préproduction, runbooks et ADR.

Ces tests ne contactent ni Docker, ni GitHub, ni le réseau : ils vérifient que
les outils et la documentation d'exploitation restent cohérents, et exécutent
seulement les modes sûrs (`--help`, `--dry-run`, `--verifier`) sur des archives
factices créées dans un dossier temporaire.

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import gzip
import io
import os
import re
import subprocess
import tarfile
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from outils import bash, exiger, manquant

RACINE = Path(__file__).resolve().parents[1]
DOSSIER_SCRIPTS = RACINE / "scripts"

SCRIPTS = (
    "appliquer-protection.sh",
    "verifier-sante.sh",
    "restaurer.sh",
    "deployer.sh",
    "sauvegarder.sh",
    "fusionner-pr.sh",
)

RUNBOOKS = (
    "incident",
    "restauration",
    "mise-a-jour",
    "rotation-secrets",
    "deploiement-unraid",
)

ADR = (
    "0001-protection-branche",
    "0002-fxserver-epingle",
)

MOTIFS_SECRETS_CONNUS = (
    re.compile(r"ghp_[A-Za-z0-9]{30,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{30,}"),
    re.compile(r"cfxk_[A-Za-z0-9]{20,}"),
    re.compile(r"AGE-SECRET-KEY-[A-Z0-9]{20,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
)

AFFECTATION_SENSIBLE = re.compile(
    r"(?i)\b(?:password|passwd|mot_de_passe|secret|token|api_key|licence_key|license_key)\b"
    r"\s*[:=]\s*['\"]?([^\s'\"]{8,})"
)


def lire(chemin: Path) -> str:
    return chemin.read_text(encoding="utf-8")


def lancer(*arguments: str, variables: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    """Exécute une commande bash depuis la racine, avec des chemins relatifs."""
    executable = bash()
    if executable is None:
        manquant("bash")
    environnement = os.environ.copy()
    if variables:
        environnement.update(variables)
    return subprocess.run(
        [executable, *arguments],
        cwd=str(RACINE),
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        env=environnement,
    )


def ecrire_archives(dossier: Path) -> None:
    with gzip.open(dossier / "base.sql.gz", "wb") as fichier:
        fichier.write(b"-- dump de test\nCREATE TABLE exemple (id INT);\n")
    for nom, chemin, contenu in (
        ("txdata.tar.gz", "txAdmin.db", b"txadmin"),
        ("maps.tar.gz", "maps.json", b'{"sections": []}'),
    ):
        with tarfile.open(dossier / nom, "w:gz") as archive:
            entree = tarfile.TarInfo(chemin)
            entree.size = len(contenu)
            archive.addfile(entree, io.BytesIO(contenu))


def chemin_relatif(chemin: Path) -> str:
    """Chemin relatif à la racine, au format accepté par bash sous WSL."""
    return os.path.relpath(chemin, RACINE).replace(os.sep, "/")


class ScriptsExploitation(unittest.TestCase):
    """Les scripts d'exploitation sont exécutables, sûrs et documentés."""

    def setUp(self) -> None:
        exiger(self, "bash", bash())

    def test_scripts_presents_et_non_vides(self) -> None:
        for nom in SCRIPTS:
            with self.subTest(script=nom):
                chemin = DOSSIER_SCRIPTS / nom
                self.assertTrue(chemin.is_file(), "script manquant")
                self.assertGreater(len(lire(chemin).strip()), 500, "script vide ou presque")

    def test_scripts_ont_set_euo_pipefail(self) -> None:
        for nom in SCRIPTS:
            with self.subTest(script=nom):
                self.assertIn("set -euo pipefail", lire(DOSSIER_SCRIPTS / nom))

    def test_aide_avant_tout_prerequis(self) -> None:
        for nom in SCRIPTS:
            with self.subTest(script=nom):
                resultat = lancer(f"scripts/{nom}", "--help")
                self.assertEqual(resultat.returncode, 0, resultat.stderr)
                sortie = (resultat.stdout + resultat.stderr).lower()
                self.assertIn("usage", sortie, "aide absente ou illisible")

    def test_option_inconnue_refusee(self) -> None:
        for nom in SCRIPTS:
            with self.subTest(script=nom):
                resultat = lancer(f"scripts/{nom}", "--option-qui-n-existe-pas")
                self.assertNotEqual(resultat.returncode, 0, "option inconnue acceptée")

    def test_syntaxe_bash(self) -> None:
        for nom in SCRIPTS:
            with self.subTest(script=nom):
                resultat = lancer("-n", f"scripts/{nom}")
                self.assertEqual(resultat.returncode, 0, resultat.stderr)

    def test_aucun_secret_en_clair(self) -> None:
        for nom in SCRIPTS:
            texte = lire(DOSSIER_SCRIPTS / nom)
            with self.subTest(script=nom):
                for motif in MOTIFS_SECRETS_CONNUS:
                    self.assertIsNone(
                        motif.search(texte), f"secret potentiel dans {nom}"
                    )
                for numero, ligne in enumerate(texte.splitlines(), start=1):
                    depouillee = ligne.strip()
                    if not depouillee or depouillee.startswith("#"):
                        continue
                    trouve = AFFECTATION_SENSIBLE.search(ligne)
                    if trouve is None:
                        continue
                    valeur = trouve.group(1)
                    self.assertTrue(
                        valeur.startswith(("$", "change_")),
                        f"{nom}:{numero} contient une valeur secrète en clair",
                    )


class ProtectionBranche(unittest.TestCase):
    """Le script de protection lit ou applique le JSON, sans le modifier."""

    def test_script_utilise_gh_et_le_json_versionne(self) -> None:
        texte = lire(DOSSIER_SCRIPTS / "appliquer-protection.sh")
        self.assertIn("gh api", texte)
        self.assertIn(".github/branch-protection.json", texte)
        for option in ("--check", "--apply", "--help"):
            with self.subTest(option=option):
                self.assertIn(option, texte)

    def test_script_explique_le_plan_github(self) -> None:
        texte = lire(DOSSIER_SCRIPTS / "appliquer-protection.sh")
        self.assertIn("GitHub Pro", texte)
        self.assertIn("dépôt public", texte)
        self.assertNotIn("gh api -X PUT", texte.split("--apply", 1)[0])

    def test_le_json_n_est_pas_modifie_par_l_aide(self) -> None:
        chemin = RACINE / ".github" / "branch-protection.json"
        avant = chemin.read_bytes()
        lancer("scripts/appliquer-protection.sh", "--help")
        self.assertEqual(chemin.read_bytes(), avant, "le JSON de protection a changé")


class SanteEtDeploiement(unittest.TestCase):
    """Les modes à blanc ne touchent ni Docker, ni la production, ni les secrets."""

    def test_verifier_sante_dry_run(self) -> None:
        secret = "https://exemple.invalid/webhook-tres-secret"
        resultat = lancer(
            "scripts/verifier-sante.sh",
            "--dry-run",
            variables={"ALERT_WEBHOOK": secret},
        )
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertIn("Mode à blanc", resultat.stdout)
        self.assertNotIn(secret, resultat.stdout + resultat.stderr)
        self.assertIn("healthcheck.sh", resultat.stdout)

    def test_deployer_dry_run_accepte_un_digest(self) -> None:
        digest = "a" * 64
        reference = f"ghcr.io/exemple/gunfight@sha256:{digest}"
        resultat = lancer(
            "scripts/deployer.sh", "--dry-run", "--image-ref", reference
        )
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertIn("Mode à blanc", resultat.stdout)
        self.assertIn(reference, resultat.stdout)
        self.assertIn("Rien n'a été modifié", resultat.stdout)

    def test_deployer_refuse_un_tag_mutable(self) -> None:
        resultat = lancer(
            "scripts/deployer.sh",
            "--dry-run",
            "--image-ref",
            "ghcr.io/exemple/gunfight:v1.2.3",
        )
        self.assertNotEqual(resultat.returncode, 0)
        self.assertIn("sha256", resultat.stderr.lower())

    def test_deployer_sans_image_ne_fait_rien(self) -> None:
        resultat = lancer(
            "scripts/deployer.sh", "--dry-run", variables={"IMAGE_REF": ""}
        )
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertIn("Aucune image", resultat.stdout)

    def test_sauvegarde_documente_ses_options(self) -> None:
        texte = lire(DOSSIER_SCRIPTS / "sauvegarder.sh")
        for attendu in (
            "AGE_RECIPIENT",
            "RCLONE_REMOTE",
            "flock",
            "manifeste.sha256",
            "14",
            "4",
        ):
            with self.subTest(attendu=attendu):
                self.assertIn(attendu, texte)
        # La production n'a plus le mot de passe root dans l'environnement :
        # le dump doit lire le secret monté, avec la variable en repli dev.
        self.assertIn("/run/secrets/db_root_password", texte)
        self.assertIn("MARIADB_ROOT_PASSWORD", texte)

    def test_deployer_met_a_jour_image_ref(self) -> None:
        texte = lire(DOSSIER_SCRIPTS / "deployer.sh")
        self.assertIn("mettre_a_jour_env", texte)
        self.assertIn("IMAGE_REF=", texte)
        self.assertIn('mktemp .env.XXXXXX', texte)


class Restauration(unittest.TestCase):
    """La vérification et l'extraction restent locales et sans Docker."""

    def test_verifier_archives_factices(self) -> None:
        with tempfile.TemporaryDirectory(prefix=".tmp-ops-", dir=RACINE) as temporaire:
            dossier = Path(temporaire)
            ecrire_archives(dossier)
            resultat = lancer("scripts/restaurer.sh", "--verifier", chemin_relatif(dossier))
            self.assertEqual(resultat.returncode, 0, resultat.stderr)
            self.assertIn("Les archives sont valides.", resultat.stdout)

    def test_verifier_refuse_une_archive_manquante(self) -> None:
        with tempfile.TemporaryDirectory(prefix=".tmp-ops-", dir=RACINE) as temporaire:
            resultat = lancer(
                "scripts/restaurer.sh", "--verifier", chemin_relatif(Path(temporaire))
            )
            self.assertNotEqual(resultat.returncode, 0)
            self.assertIn("MANQUANTE", resultat.stderr)

    def test_extraction_et_refus_d_ecrasement(self) -> None:
        with tempfile.TemporaryDirectory(prefix=".tmp-ops-", dir=RACINE) as temporaire:
            dossier = Path(temporaire)
            ecrire_archives(dossier)
            destination = dossier / "extraction"
            resultat = lancer(
                "scripts/restaurer.sh",
                "--oui",
                "--destination",
                chemin_relatif(destination),
                chemin_relatif(dossier),
            )
            self.assertEqual(resultat.returncode, 0, resultat.stderr)
            self.assertIn("dump de test", lire(destination / "base.sql"))
            self.assertTrue((destination / "txdata" / "txAdmin.db").is_file())
            self.assertTrue((destination / "maps" / "maps.json").is_file())

            marqueur = destination / "a-ne-pas-effacer"
            marqueur.write_text("present", encoding="utf-8")
            refuse = lancer(
                "scripts/restaurer.sh",
                "--oui",
                "--destination",
                chemin_relatif(destination),
                chemin_relatif(dossier),
            )
            self.assertNotEqual(refuse.returncode, 0)
            self.assertTrue(marqueur.is_file(), "dossier non vide écrasé sans --force")

    def test_refuse_un_parent_de_la_racine(self) -> None:
        with tempfile.TemporaryDirectory(prefix=".tmp-ops-", dir=RACINE) as temporaire:
            dossier = Path(temporaire)
            ecrire_archives(dossier)
            resultat = lancer(
                "scripts/restaurer.sh",
                "--oui",
                "--destination",
                "..",
                chemin_relatif(dossier),
            )
            self.assertNotEqual(resultat.returncode, 0, "parent de la racine accepté")
            self.assertIn("Destination refusée", resultat.stderr)

    def test_script_ne_touche_pas_la_production(self) -> None:
        texte = lire(DOSSIER_SCRIPTS / "restaurer.sh")
        self.assertNotIn("gunfight-prod-", texte)
        self.assertNotIn("docker compose", texte)
        self.assertIn("gunfight-restore", texte)


class Preproduction(unittest.TestCase):
    """Le fichier staging est autonome et n'entre pas en collision avec la prod."""

    FICHIER = RACINE / "docker-compose.staging.yml"

    def test_fichier_present_et_complet(self) -> None:
        self.assertTrue(self.FICHIER.is_file(), "docker-compose.staging.yml manquant")
        texte = lire(self.FICHIER)
        self.assertGreater(len(texte), 500)
        self.assertIn("name: gunfight-staging", texte)
        self.assertIn("${STAGING_IMAGE_REF", texte)

    def test_ports_et_volumes_isoles(self) -> None:
        texte = lire(self.FICHIER)
        for attendu in (
            "30121:30120/tcp",
            "30121:30120/udp",
            "127.0.0.1:40121:40120/tcp",
            "gunfight-staging-txdata",
            "gunfight-staging-dbdata",
            "gunfight-staging-maps",
        ):
            with self.subTest(attendu=attendu):
                self.assertIn(attendu, texte)
        self.assertNotIn("gunfight-prod-", texte)
        self.assertNotIn("container_name: gunfight-fxserver", texte)
        self.assertNotIn("container_name: gunfight-mariadb", texte)

    def test_pas_de_build_et_amorcage_des_maps(self) -> None:
        texte = lire(self.FICHIER)
        self.assertNotRegex(texte, r"(?m)^\s*build:\s*")
        self.assertRegex(texte, r'GF_SEED_MAPS:\s*"?true"?')
        self.assertIn("mariadb:11.4@sha256:", texte)

    def test_secrets_et_isolation_reseau(self) -> None:
        texte = lire(self.FICHIER)
        self.assertNotRegex(texte, r"(?m)^\s*env_file:")
        self.assertIn("MARIADB_ROOT_PASSWORD_FILE: /run/secrets/db_root_password", texte)
        self.assertIn("MARIADB_PASSWORD_FILE: /run/secrets/db_password", texte)
        self.assertIn("internal: true", texte)
        self.assertIn("cap_drop: [ALL]", texte)
        self.assertIn("no-new-privileges:true", texte)
        self.assertNotIn("MARIADB_ROOT_PASSWORD: ${", texte)


class GabaritUnraid(unittest.TestCase):
    """Le gabarit Unraid ne doit pas réintroduire le montage complet."""

    FICHIER = RACINE / "deploy" / "unraid" / "Gunfight-FXServer.xml"

    def racine(self) -> ET.Element:
        return ET.parse(self.FICHIER).getroot()

    def configs(self) -> dict[str, ET.Element]:
        return {
            config.get("Target", ""): config
            for config in self.racine().findall("Config")
        }

    def test_gabarit_present_et_valide(self) -> None:
        self.assertTrue(self.FICHIER.is_file(), "gabarit Unraid manquant")
        racine = self.racine()
        self.assertEqual(racine.tag, "Container")
        self.assertEqual(racine.findtext("Name"), "Gunfight-FXServer")
        self.assertEqual(
            racine.findtext("Repository"),
            "ghcr.io/quentingimenez/fivemgunfight:main",
        )

    def test_aucun_montage_de_server_data_complet(self) -> None:
        cibles = {
            config.get("Target", "")
            for config in self.racine().findall("Config")
            if config.get("Type") == "Path"
        }
        self.assertNotIn("/opt/fivem/server-data", cibles)
        self.assertEqual(
            cibles,
            {
                "/opt/fivem/server-data/resources/[gunfight]/gf_maps/data",
                "/opt/fivem/server-data/resources/[gunfight]/gf_lobby/data",
                "/opt/fivem/server-data/resources/[gunfight]/gf_thumbs/thumbs",
                "/opt/fivem/server-data/resources/[gunfight]/gf_vehicles/custom",
                "/opt/fivem/txData",
            },
        )

    def test_personnages_et_schema_sur_base_existante(self) -> None:
        personnages = [
            config
            for config in self.racine().findall("Config")
            if config.get("Target")
            == "/opt/fivem/server-data/resources/[gunfight]/gf_lobby/data"
        ]
        self.assertEqual(len(personnages), 1)
        self.assertEqual(
            personnages[0].text,
            "/mnt/user/appdata/fivemgunfight/characters",
        )
        self.assertEqual(personnages[0].get("Mode"), "rw")
        self.assertEqual(personnages[0].get("Required"), "true")
        runbook = lire(RACINE / "docs" / "runbooks" / "deploiement-unraid.md")
        self.assertIn("01-schema.sql", runbook)
        self.assertIn("gf_stats_players", runbook)

    def test_amorcage_des_maps_et_heritage(self) -> None:
        racine = self.racine()
        configs = self.configs()
        self.assertEqual(configs["GF_SEED_MAPS"].text, "true")
        self.assertEqual(configs["GF_SEED_DATA"].text, "true")
        self.assertEqual(configs["TXADMIN"].text, "false")
        self.assertEqual(racine.findtext("Network"), "fivem-net")
        self.assertIsNone(racine.find("DateInstalled"))
        ports = {
            (config.get("Target"), config.get("Mode"))
            for config in racine.findall("Config")
            if config.get("Type") == "Port"
        }
        self.assertEqual(
            ports,
            {("30120", "tcp"), ("30120", "udp"), ("40120", "tcp")},
        )

    def test_secrets_vides_et_masques(self) -> None:
        configs = self.configs()
        for nom in ("LICENSE_KEY", "STEAM_WEB_API_KEY", "MARIADB_PASSWORD"):
            with self.subTest(variable=nom):
                config = configs[nom]
                self.assertEqual((config.text or "").strip(), "")
                self.assertEqual(config.get("Mask"), "true")


class DocumentationExploitation(unittest.TestCase):
    """Runbooks, ADR et index sont présents et reliés depuis le README."""

    def test_runbooks_presents_et_structures(self) -> None:
        for nom in RUNBOOKS:
            chemin = RACINE / "docs" / "runbooks" / f"{nom}.md"
            with self.subTest(runbook=nom):
                self.assertTrue(chemin.is_file(), "runbook manquant")
                texte = lire(chemin)
                self.assertGreater(len(texte), 600, "runbook vide ou presque")
                self.assertIn("bjectif", texte, "section « objectif » absente")
                self.assertIn("rification", texte, "section « vérification » absente")

    def test_adr_presents(self) -> None:
        for nom in ADR:
            chemin = RACINE / "docs" / "adr" / f"{nom}.md"
            with self.subTest(adr=nom):
                self.assertTrue(chemin.is_file(), "ADR manquant")
                texte = lire(chemin)
                self.assertGreater(len(texte), 400, "ADR vide ou presque")
                self.assertIn("Statut", texte, "statut absent de l'ADR")

    def test_readme_relie_runbooks_et_adr(self) -> None:
        texte = lire(RACINE / "README.md")
        for nom in RUNBOOKS:
            with self.subTest(runbook=nom):
                self.assertIn(f"docs/runbooks/{nom}.md", texte)
        for nom in ADR:
            with self.subTest(adr=nom):
                self.assertIn(f"docs/adr/{nom}.md", texte)

    def test_index_docs_relie_les_nouveaux_documents(self) -> None:
        texte = lire(RACINE / "docs" / "README.md")
        for nom in RUNBOOKS:
            with self.subTest(runbook=nom):
                self.assertIn(f"runbooks/{nom}.md", texte)
        for nom in ADR:
            with self.subTest(adr=nom):
                self.assertIn(f"adr/{nom}.md", texte)

    def test_security_documente_la_rotation(self) -> None:
        texte = lire(RACINE / "SECURITY.md")
        self.assertIn("rotation-secrets.md", texte)
        self.assertIn("Versions supportées", texte)

    def test_runbooks_restauration_et_migration_volumes(self) -> None:
        restauration = lire(RACINE / "docs" / "runbooks" / "restauration.md")
        self.assertNotIn("env_file", restauration)
        self.assertNotIn("--env-file", restauration)
        self.assertIn("/run/secrets/db_root_password", restauration)
        self.assertIn("/run/secrets/db_password", restauration)
        self.assertIn("MARIADB_PASSWORD_FILE", restauration)
        migration = lire(RACINE / "docs" / "runbooks" / "mise-a-jour.md")
        self.assertIn("gunfight-prod-txdata", migration)
        self.assertIn("chown -R 10001:10001", migration)

    def test_editorconfig_present(self) -> None:
        chemin = RACINE / ".editorconfig"
        self.assertTrue(chemin.is_file(), ".editorconfig manquant")
        texte = lire(chemin)
        for attendu in ("root = true", "charset = utf-8", "end_of_line = lf", "[*.bat]"):
            with self.subTest(attendu=attendu):
                self.assertIn(attendu, texte)

    def test_gitignore_couvre_archives_et_extractions(self) -> None:
        texte = lire(RACINE / ".gitignore")
        for attendu in (
            ".env",
            ".env.*",
            "secrets/",
            "backups/",
            "restauration/",
            "*.sql.gz",
            "*.tar.gz",
            "*.age",
        ):
            with self.subTest(attendu=attendu):
                self.assertIn(attendu, texte)


# Faux `gh` : journalise chaque appel et répond selon des variables FAUX_*.
FAUX_GH = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAUX_JOURNAL"
case "$1 $2" in
  "pr checks") exit "${FAUX_CHECKS:-0}" ;;
  "pr merge") exit 0 ;;
  "pr view") echo "${FAUX_ETAT:-MERGED} abc1234def" ;;
  "run list") [ -n "${FAUX_RUNS-101 102}" ] && printf '%s\n' ${FAUX_RUNS-101 102}; exit 0 ;;
  "run watch") [ "$3" = "${FAUX_ROUGE:-}" ] && exit 1; exit 0 ;;
  "run view") echo "https://exemple.test/runs/$3" ;;
esac
exit 0
"""


class FusionPR(unittest.TestCase):
    """`fusionner-pr.sh` : checks verts, squash, puis CI de main suivie au bout."""

    def setUp(self) -> None:
        exiger(self, "bash", bash())

    def lancer_fusion(self, *arguments: str, **faux: str) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        with tempfile.TemporaryDirectory(dir=RACINE) as dossier:
            gh = Path(dossier) / "gh"
            gh.write_text(FAUX_GH, encoding="utf-8", newline="\n")
            gh.chmod(0o755)
            journal = Path(dossier) / "journal.txt"
            journal.write_text("", encoding="utf-8")
            variables = {
                "GH": chemin_relatif(gh),
                "FAUX_JOURNAL": chemin_relatif(journal),
                "INTERVALLE": "0",
                "ESSAIS_RUNS": "2",
            }
            variables.update({f"FAUX_{cle.upper()}": valeur for cle, valeur in faux.items()})
            resultat = lancer("scripts/fusionner-pr.sh", *arguments, variables=variables)
            appels = [ligne for ligne in lire(journal).splitlines() if ligne]
        return resultat, appels

    def indice(self, appels: list[str], debut: str) -> int:
        for position, appel in enumerate(appels):
            if appel.startswith(debut):
                return position
        self.fail(f"appel « {debut} » absent : {appels}")

    def test_checks_verts_fusion_puis_suivi_de_main(self) -> None:
        resultat, appels = self.lancer_fusion("12")
        self.assertEqual(resultat.returncode, 0, resultat.stdout + resultat.stderr)
        self.assertLess(self.indice(appels, "pr checks 12"), self.indice(appels, "pr merge 12"))
        self.assertIn("--squash", appels[self.indice(appels, "pr merge 12")])
        liste = appels[self.indice(appels, "run list")]
        self.assertIn("--branch main", liste)
        self.assertIn("abc1234def", liste, "les runs suivis doivent être ceux du commit de fusion")
        self.assertLess(self.indice(appels, "pr merge 12"), self.indice(appels, "run watch 101"))
        self.indice(appels, "run watch 102")

    def test_checks_rouges_aucune_fusion(self) -> None:
        resultat, appels = self.lancer_fusion("12", checks="1")
        self.assertNotEqual(resultat.returncode, 0)
        self.assertFalse([a for a in appels if a.startswith("pr merge")], "fusion malgré un check rouge")

    def test_main_rouge_fait_echouer_et_donne_le_lien(self) -> None:
        resultat, _ = self.lancer_fusion("12", rouge="102")
        self.assertNotEqual(resultat.returncode, 0, "main rouge doit faire échouer le script")
        self.assertIn("https://exemple.test/runs/102", resultat.stdout + resultat.stderr)

    def test_aucun_run_sur_main_echoue(self) -> None:
        resultat, _ = self.lancer_fusion("12", runs="")
        self.assertNotEqual(resultat.returncode, 0, "aucun run de main trouvé : rien n'a été vérifié")

    def test_pr_non_fusionnee_echoue(self) -> None:
        resultat, appels = self.lancer_fusion("12", etat="OPEN")
        self.assertNotEqual(resultat.returncode, 0)
        self.assertFalse([a for a in appels if a.startswith("run watch")])

    def test_numero_invalide_refuse(self) -> None:
        resultat, appels = self.lancer_fusion("douze")
        self.assertNotEqual(resultat.returncode, 0)
        self.assertEqual(appels, [], "aucun appel à gh avec un numéro invalide")


if __name__ == "__main__":
    unittest.main()
