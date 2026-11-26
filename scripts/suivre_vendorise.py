#!/usr/bin/env python3
"""Vérifie les dépendances vendorisées (copies locales non suivies par Dependabot).

L'outil est en lecture seule : il ne télécharge, ne modifie et n'écrit rien sur
le disque. Il sert à contrôler que la copie vendorisée correspond bien à la
version et à l'empreinte notées dans `vendorise.json`, puis à interroger l'amont
GitHub pour détecter une montée ou un avis de sécurité.

Exemples d'usage :

  python scripts/suivre_vendorise.py
  python scripts/suivre_vendorise.py --verifier
  python scripts/suivre_vendorise.py --empreinte "server-data/resources/[standalone]/oxmysql"
  python scripts/suivre_vendorise.py --amont
  python scripts/suivre_vendorise.py --amont --depuis-json amont.json

La variable d'environnement GH choisit l'exécutable GitHub CLI (défaut « gh »).
En mode --amont --depuis-json, les réponses sont lues dans un fichier au format
(une clé par entrée de vendorise.json, absente = erreur de JSON) :

  {
    "overextended/oxmysql": {
      "release": {"tag_name": "v2.14.3"},
      "advisories": [ <objets bruts de l'API /security-advisories> ]
    }
  }

Les modes sont mutuellement exclusifs ; --verifier est le défaut.

Codes de sortie : 0 si tout correspond et que l'amont est propre, 1 si au
moins une entrée présente un écart, une montée ou un avis, 2 si le JSON est
illisible/invalide, qu'un fichier obligatoire manque ou que les arguments sont
incorrects, 3 si l'appel gh échoue (absent, non authentifié, sortie illisible
ou erreur réseau).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
FICHIER_VENDORISE = (
    RACINE / "server-data" / "resources" / "[standalone]" / "vendorise.json"
)
CLES_ENTREE = ("nom", "version", "depot", "licence", "dossier", "empreinte")
VERSION_LUA = re.compile(
    r"""\bversion\b\s*=?\s*(['"])(.*?)\1""", re.IGNORECASE
)
HEX = re.compile(r"^[0-9a-f]{64}$")


def empreinte(dossier: str | Path) -> str:
    """Empreinte sha256 (hex minuscule) du contenu d'un dossier.

    Les fichiers sont parcourus récursivement, triés par chemin relatif POSIX.
    Pour chacun, on hache le chemin UTF-8, un octet nul, le contenu brut avec
    les séquences CRLF remplacées par LF, puis un octet nul. Le résultat est
    ainsi identique sous Windows (autocrlf) et sous Linux.

    Lève OSError si le dossier n'existe pas ou n'est pas un dossier, et
    ValueError si le chemin est vide.
    """
    chemin = Path(dossier)
    if not str(chemin):
        raise ValueError("Le chemin du dossier est vide.")
    if not chemin.is_dir():
        raise OSError(f"Dossier introuvable ou non valide : {chemin}")

    hachage = hashlib.sha256()
    fichiers = sorted(
        (fichier for fichier in chemin.rglob("*") if fichier.is_file()),
        key=lambda fichier: fichier.relative_to(chemin).as_posix(),
    )
    for fichier in fichiers:
        relatif = fichier.relative_to(chemin).as_posix()
        hachage.update(relatif.encode("utf-8"))
        hachage.update(b"\0")
        hachage.update(fichier.read_bytes().replace(b"\r\n", b"\n"))
        hachage.update(b"\0")
    return hachage.hexdigest()


def _composants(jeton: str) -> list[int] | None:
    """Composants numériques d'une version (préfixe « v » ignoré), sinon None."""
    texte = str(jeton).strip().strip("`'\"()[]{}.,;:!?")
    if texte[:1] in ("v", "V"):
        texte = texte[1:]
    morceaux = texte.split(".")
    if not morceaux or any(not morceau.isdigit() for morceau in morceaux):
        return None
    return [int(morceau) for morceau in morceaux]


def comparer_versions(gauche: str, droite: str) -> int:
    """Compare deux versions : -1 si gauche < droite, 0 si égale, 1 si >.

    Les composants numériques sont comparés en ignorant le préfixe « v ». Une
    version illisible est traitée comme plus ancienne que l'autre pour ne pas
    masquer une montée disponible.
    """
    a = _composants(gauche)
    b = _composants(droite)
    if a is None and b is None:
        return 0
    if a is None:
        return -1
    if b is None:
        return 1
    for indice in range(max(len(a), len(b))):
        va = a[indice] if indice < len(a) else 0
        vb = b[indice] if indice < len(b) else 0
        if va != vb:
            return -1 if va < vb else 1
    return 0


def version_manifeste(manifest: Path) -> str | None:
    """Version déclarée dans un fxmanifest.lua (guillemets simples ou doubles)."""
    try:
        texte = manifest.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    correspondance = VERSION_LUA.search(texte)
    return correspondance.group(2) if correspondance else None


def lire_vendorise(fichier: Path) -> tuple[list[dict] | None, str]:
    """Lit et valide le JSON de suivi ; renvoie (entrees, message d'erreur)."""
    try:
        texte = fichier.read_text(encoding="utf-8")
    except OSError as erreur:
        return None, f"Fichier vendorise.json illisible : {fichier} ({erreur})"
    try:
        entrees = json.loads(texte)
    except ValueError as erreur:
        return None, f"JSON illisible dans {fichier} : {erreur}"
    if not isinstance(entrees, list) or any(
        not isinstance(entree, dict) for entree in entrees
    ):
        return None, f"JSON invalide dans {fichier} : liste d'objets attendue."
    for entree in entrees:
        manquantes = [cle for cle in CLES_ENTREE if not isinstance(entree.get(cle), str)]
        if manquantes:
            return None, (
                f"JSON invalide dans {fichier} : entrée {entree.get('nom', '?')} "
                f"sans clé(s) texte : {', '.join(manquantes)}."
            )
        if not HEX.fullmatch(entree["empreinte"]):
            return None, (
                f"JSON invalide dans {fichier} : empreinte de "
                f"{entree['nom']} non hexadécimale (64 caractères attendus)."
            )
    return entrees, ""


def _chemin_dossier(valeur: str) -> Path:
    """Résout un dossier noté dans le JSON (absolu ou relatif à la racine)."""
    chemin = Path(valeur)
    return chemin if chemin.is_absolute() else RACINE / chemin


def verifier(entrees: list[dict]) -> int:
    """Compare versions et empreintes des copies ; affiche OK ou ECART."""
    code = 0
    for entree in entrees:
        dossier = _chemin_dossier(entree["dossier"])
        manifest = dossier / "fxmanifest.lua"
        if not dossier.is_dir():
            print(f"ECART {entree['nom']} : dossier introuvable : {dossier}")
            code = 1
            continue
        if not manifest.is_file():
            print(f"ECART {entree['nom']} : fxmanifest.lua introuvable : {manifest}")
            code = 1
            continue
        version = version_manifeste(manifest)
        if version is None:
            print(f"ECART {entree['nom']} : version absente de {manifest}")
            code = 1
            continue
        try:
            calculee = empreinte(dossier)
        except (OSError, ValueError) as erreur:
            print(f"ECART {entree['nom']} : empreinte impossible ({erreur})")
            code = 1
            continue
        if version == entree["version"] and calculee == entree["empreinte"]:
            print(f"OK {entree['nom']} {version} {calculee}")
            continue
        code = 1
        print(f"ECART {entree['nom']} :")
        if version != entree["version"]:
            print(f"  version installée {version} vs attendue {entree['version']}")
        if calculee != entree["empreinte"]:
            print(f"  empreinte calculée {calculee} vs attendue {entree['empreinte']}")
    return code


def _appel_gh(arguments: list[str]) -> object:
    """Appelle gh et renvoie le JSON décodé ; lève RuntimeError en cas d'échec."""
    gh = os.environ.get("GH", "gh")
    commande = [gh, *arguments]
    try:
        resultat = subprocess.run(
            commande,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as erreur:
        raise RuntimeError(
            f"gh introuvable ou non exécutable ({gh}). Installe GitHub CLI puis "
            f"connecte-toi avec `gh auth login` ({erreur})."
        ) from erreur
    if resultat.returncode != 0:
        detail = (resultat.stderr or "").strip() or f"code {resultat.returncode}"
        raise RuntimeError(
            "gh a échoué (absent, non authentifié ou réseau) : "
            f"{detail}\nVérifie avec `gh auth status`."
        )
    try:
        return json.loads(resultat.stdout)
    except ValueError as erreur:
        raise RuntimeError(f"Sortie JSON de gh illisible : {erreur}") from erreur


def _donnees_amont(
    entree: dict, depuis_json: dict | None
) -> tuple[dict, list[dict]]:
    """Récupère release et avis, depuis le fichier ou via gh."""
    depot = entree["depot"]
    if depuis_json is not None:
        bloc = depuis_json.get(depot)
        if not isinstance(bloc, dict):
            raise ValueError(f"clé absente pour {depot} dans le JSON enregistré")
        release = bloc.get("release")
        avis = bloc.get("advisories")
        if not isinstance(release, dict) or not isinstance(avis, list):
            raise ValueError(
                f"bloc invalide pour {depot} : release (objet) et advisories (liste) attendus"
            )
        if any(not isinstance(element, dict) for element in avis):
            raise ValueError(f"avis invalides pour {depot} : liste d'objets attendue")
        return release, avis
    release = _appel_gh(["api", f"repos/{depot}/releases/latest"])
    avis = _appel_gh(["api", f"repos/{depot}/security-advisories"])
    if not isinstance(release, dict) or not isinstance(avis, list) or any(
        not isinstance(element, dict) for element in avis
    ):
        raise RuntimeError(f"sortie gh invalide pour {depot}")
    return release, avis


def _versions_ouverture(
    plage: str,
) -> tuple[str | None, bool, str | None, bool]:
    """Interprète une plage semver en deux bornes avec leur inclusivité.

    Renvoie (basse, basse_incluse, haute, haute_incluse). Les formes prises en
    charge sont `< x`, `<= x`, `= x`, `>= x`, `> x` et les plages avec virgule
    (ET logique). `= x` fixe les deux bornes à x, toutes deux inclusives. Une
    plage illisible renvoie (None, False, None, False) : on s'appuie alors sur
    patched_versions.
    """
    texte = str(plage or "").strip()
    bornes = [part.strip() for part in texte.split(",") if part.strip()]
    if not bornes:
        return None, False, None, False
    basse = None
    basse_incluse = True
    haute = None
    haute_incluse = True
    for borne in bornes:
        correspondance = re.match(r"^(<=|>=|<|>|=)\s*(\S+)$", borne)
        if not correspondance:
            return None, False, None, False
        op, version = correspondance.groups()
        if _composants(version) is None:
            return None, False, None, False
        if op in ("<", "<="):
            haute = version
            haute_incluse = op == "<="
        elif op == "=":
            basse = version
            basse_incluse = True
            haute = version
            haute_incluse = True
        else:
            basse = version
            basse_incluse = op == ">="
    return basse, basse_incluse, haute, haute_incluse


def _normaliser_version_corrigee(valeur: object) -> str:
    """Retire un éventuel préfixe d'opérateur d'une version corrigée.

    L'API GitHub peut renvoyer « >= 2.14.4 » ou « 2.14.4 » : la comparaison
    n'utilise que la version nue, tandis que l'affichage garde la valeur brute.
    """
    texte = str(valeur).strip()
    return re.sub(r"^(<=|>=|<|>|=)\s*", "", texte).strip()


def avis_touche(avis: dict, installee: str) -> bool:
    """Dit si un avis concerne la version installée ou une version antérieure.

    Une plage lisible est évaluée ; si elle est illisible, on s'appuie sur
    patched_versions. Un avis dont une version corrigée est strictement
    postérieure à l'installée est retenu.
    """
    vulnerabilites = avis.get("vulnerabilities")
    if not isinstance(vulnerabilites, list):
        vulnerabilites = []
    corrigee_ulterieure = False
    for vulnerabilite in vulnerabilites:
        if not isinstance(vulnerabilite, dict):
            continue
        corriges = vulnerabilite.get("patched_versions")
        if isinstance(corriges, str):
            corriges = [corriges]
        if not isinstance(corriges, list):
            corriges = []
        for corrigee in corriges:
            if comparer_versions(_normaliser_version_corrigee(corrigee), installee) > 0:
                corrigee_ulterieure = True
        plage = str(vulnerabilite.get("vulnerable_version_range") or "")
        basse, basse_incluse, haute, haute_incluse = _versions_ouverture(plage)
        if basse is None and haute is None:
            continue
        if basse is not None:
            cmp_basse = comparer_versions(installee, basse)
            if cmp_basse < 0 or (cmp_basse == 0 and not basse_incluse):
                continue
        if haute is not None:
            cmp_haute = comparer_versions(installee, haute)
            if cmp_haute > 0 or (cmp_haute == 0 and not haute_incluse):
                continue
        return True
    return corrigee_ulterieure


def _version_corrigee(avis: dict) -> str:
    """Première version corrigée d'un avis, ou « ? » si absente."""
    for vulnerabilite in avis.get("vulnerabilities") or []:
        if not isinstance(vulnerabilite, dict):
            continue
        corriges = vulnerabilite.get("patched_versions")
        if isinstance(corriges, str):
            return corriges
        if isinstance(corriges, list) and corriges:
            return str(corriges[0])
    return "?"


def amont(entrees: list[dict], depuis_json: dict | None) -> int:
    """Compare l'installé à la dernière release et aux avis de sécurité."""
    code = 0
    for entree in entrees:
        try:
            release, avis = _donnees_amont(entree, depuis_json)
        except (RuntimeError, ValueError) as erreur:
            print(f"ERREUR {entree['nom']} : {erreur}", file=sys.stderr)
            return 2 if depuis_json is not None else 3
        tag = release.get("tag_name")
        if not isinstance(tag, str) or not tag.strip():
            print(
                f"ERREUR {entree['nom']} : tag_name absent de la release",
                file=sys.stderr,
            )
            return 2 if depuis_json is not None else 3
        installee = entree["version"]
        derniere = tag
        montante = comparer_versions(derniere, installee) > 0
        print(f"{entree['nom']} : version installée {installee}, dernière {derniere}")
        if montante:
            code = 1
            print(f"  montée disponible : {installee} -> {derniere}")
        else:
            print("  à jour : aucune montée disponible")

        touches = [element for element in avis if avis_touche(element, installee)]
        if not touches:
            print("  aucun avis ne concerne cette copie")
            continue
        code = 1
        for element in touches:
            print(
                f"  AVIS {element.get('ghsa_id', '?')} [{element.get('severity', '?')}] "
                f"{element.get('summary', '?')} "
                f"(version corrigée : {_version_corrigee(element)})"
            )
    return code


def _lire_fichier_amont(fichier: Path) -> tuple[dict | None, str]:
    """Lit le JSON enregistré des réponses gh pour les tests hors ligne."""
    try:
        texte = fichier.read_text(encoding="utf-8")
    except OSError as erreur:
        return None, f"Fichier JSON illisible : {fichier} ({erreur})"
    try:
        donnees = json.loads(texte)
    except ValueError as erreur:
        return None, f"JSON illisible dans {fichier} : {erreur}"
    if not isinstance(donnees, dict):
        return None, f"JSON invalide dans {fichier} : objet attendu."
    return donnees, ""


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée CLI : modes mutuellement exclusifs, --verifier par défaut."""
    analyseur = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog="L'outil est en lecture seule : aucun fichier n'est modifié.",
    )
    groupe = analyseur.add_mutually_exclusive_group()
    groupe.add_argument(
        "--verifier",
        action="store_true",
        help="vérifie versions et empreintes (mode par défaut)",
    )
    groupe.add_argument(
        "--empreinte",
        metavar="DOSSIER",
        help="affiche l'empreinte sha256 du DOSSIER",
    )
    groupe.add_argument(
        "--amont",
        action="store_true",
        help="interroge l'amont GitHub (release et avis)",
    )
    analyseur.add_argument(
        "--depuis-json",
        metavar="FICHIER",
        type=Path,
        help="avec --amont : lit les réponses gh depuis FICHIER (hors ligne)",
    )
    args = analyseur.parse_args(argv)

    if args.depuis_json is not None and not args.amont:
        print(
            "--depuis-json ne peut être utilisé qu'avec --amont.",
            file=sys.stderr,
        )
        return 2

    if args.empreinte is not None:
        try:
            print(empreinte(args.empreinte))
        except (OSError, ValueError) as erreur:
            print(str(erreur), file=sys.stderr)
            return 2
        return 0

    entrees, erreur = lire_vendorise(FICHIER_VENDORISE)
    if entrees is None:
        print(erreur, file=sys.stderr)
        return 2

    if args.amont:
        depuis_json = None
        if args.depuis_json is not None:
            depuis_json, erreur = _lire_fichier_amont(args.depuis_json)
            if depuis_json is None:
                print(erreur, file=sys.stderr)
                return 2
        return amont(entrees, depuis_json)

    return verifier(entrees)


if __name__ == "__main__":
    sys.exit(main())
