#!/usr/bin/env python3
"""Pilote de test NUI d'un client FiveM unique, par la passerelle gf_testbridge.

Le pilote redémarre la passerelle par rcon, ouvre et ferme chaque page NUI,
capture l'écran avant et après, compare les deux images par SSIM, lit les
journaux serveur et client, puis ferme ce qu'il a ouvert. Les tests unitaires
injectent un contexte factice : aucun réseau, aucun Docker, aucune capture,
aucun client et aucune attente réelle.

    python scripts/verifier_nui.py
    python scripts/verifier_nui.py --pages gf_admin gf_menu --verbeux
    python scripts/verifier_nui.py --sans-client --sortie C:\\temp\\gf-nui

Codes de sortie : 0 tout passe, 1 un contrôle échoue, 2 prérequis manquant.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable

RACINE = Path(__file__).resolve().parents[1]
SCRIPTS = RACINE / "scripts"
PAGES_DEFAUT = ("gf_admin", "gf_maps", "gf_vehicles", "gf_menu")
NOM_PAGES = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SEUIL_DEFAUT = 0.98
DELAI_DEFAUT = 30.0
DORMIR_OUVERTURE = 2.0
ECART_CAPTURES = 5.5
INTERVALLE_JOURNAL = 0.2
LIGNE_PRET = "[gf_testbridge] prêt (développement)"
LIGNE_DESACTIVE = "[gf_testbridge] désactivé"
LIGNE_CLIENT = "[gf_testbridge] client prêt id="
MOTIFS_ERREUR = ("SCRIPT ERROR", "Error loading", "Failed to load")
COMMANDE_JOURNAL = [
    "docker",
    "compose",
    "-f",
    "docker-compose.yml",
    "-f",
    "docker-compose.dev.yml",
    "logs",
    "--no-color",
    "fxserver",
]
def _powershell() -> str:
    """PowerShell disponible : pwsh (7+), sinon Windows PowerShell.

    Sous WSL, le PATH ne contient pas toujours les dossiers Windows : on
    cherche aussi le chemin absolu de Windows PowerShell.
    """
    for nom in ("pwsh", "powershell", "powershell.exe"):
        trouve = shutil.which(nom)
        if trouve:
            return trouve
    windows = Path("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
    if windows.exists():
        return str(windows)
    return "powershell"


POWERSHELL = _powershell()
COMMANDE_PROCESS = [
    POWERSHELL,
    "-NoProfile",
    "-Command",
    "[bool](Get-Process -Name 'FiveM*' -ErrorAction SilentlyContinue)",
]
# FiveM refuse de démarrer hors de son propre dossier : -WorkingDirectory est
# obligatoire, sinon le processus meurt avec « launched directly from the
# shell or a web browser ».
COMMANDE_LANCEMENT = [
    POWERSHELL,
    "-NoProfile",
    "-Command",
    (
        "Start-Process -FilePath $env:GF_FIVEM_EXE "
        "-ArgumentList '+connect','127.0.0.1:30120' "
        "-WorkingDirectory (Split-Path -Parent $env:GF_FIVEM_EXE)"
    ),
]
COMMANDE_FERMETURE = [
    POWERSHELL,
    "-NoProfile",
    "-Command",
    "Get-Process -Name 'FiveM*' -ErrorAction SilentlyContinue | Stop-Process -Force",
]


def _charger(nom: str, chemin: Path):
    """Importe un module du dépôt par son chemin, sans le dupliquer."""
    if nom in sys.modules:
        return sys.modules[nom]
    if str(SCRIPTS) not in sys.path:
        sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location(nom, chemin)
    module = importlib.util.module_from_spec(spec)
    sys.modules[nom] = module
    spec.loader.exec_module(module)
    return module


fivem_rcon = _charger("fivem_rcon", SCRIPTS / "fivem_rcon.py")
comparer_rendu = _charger("comparer_rendu", SCRIPTS / "comparer_rendu.py")
journal_client = _charger("journal_client", SCRIPTS / "journal_client.py")


class PrerequisManquant(Exception):
    """Prérequis absent : sortie 2, avec un message actionnable."""


class ControleEchoue(Exception):
    """Contrôle NUI en échec : sortie 1."""


@dataclass
class Verdict:
    """Résultat d'une page, affiché en fin de course."""

    page: str
    ouvert: bool = False
    ferme: bool = False
    indice: float | None = None
    reussi: bool = False
    detail: str = ""


@dataclass
class EtatCourse:
    """État mutable d'une seule course, jamais global."""

    debut_journal: int = 0
    debut_client: dict[str, tuple[int, int]] = field(default_factory=dict)
    client_lance: bool = False
    pages_ouvertes: list[str] = field(default_factory=list)
    verdicts: list[Verdict] = field(default_factory=list)
    erreurs: list[str] = field(default_factory=list)
    derniere_capture: float = 0.0


def valider_sortie(sortie: Path, racine: Path) -> Path:
    """Résout le dossier de sortie et refuse tout chemin dans le dépôt."""
    chemin = sortie.expanduser().resolve()
    dep = racine.resolve()
    if chemin == dep or dep in chemin.parents:
        raise PrerequisManquant(
            f"Sortie refusée : {chemin} est dans le dépôt {dep}. "
            "Choisis un dossier hors du dépôt, par exemple %TEMP%\\gf-nui."
        )
    return chemin


def valider_pages(pages: list[str]) -> list[str]:
    """Refuse les noms de pages qui ne sont pas des identifiants sûrs."""
    for page in pages:
        if not NOM_PAGES.fullmatch(page):
            raise PrerequisManquant(
                f"Page invalide dans --pages : {page!r}. "
                "Utilise des identifiants de ressources (lettres, chiffres, tiret bas)."
            )
    return pages


def _lire_journal_commandes() -> list[str]:
    """Lit le journal fxserver en utf-8 tolérant, ligne par ligne."""
    resultat = subprocess.run(
        COMMANDE_JOURNAL,
        capture_output=True,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return ((resultat.stdout or "") + (resultat.stderr or "")).splitlines()


def _envoyer_rcon_reel(
    hote: str, port: int, mot_de_passe: str, delai: float
) -> Callable[[str], str | None]:
    """Fabrique le callable rcon à partir du protocole de fivem_rcon.py."""

    def envoyer(commande: str) -> str | None:
        try:
            donnees = fivem_rcon.paquet(mot_de_passe, commande)
            reponses = fivem_rcon.envoyer(hote, port, donnees, delai)
        except (OSError, ValueError) as exc:
            print(f"erreur rcon : {exc}", file=sys.stderr)
            return None
        if not reponses:
            print(
                f"rcon injoignable sur {hote}:{port} : serveur arrêté ou rcon non actif.",
                file=sys.stderr,
            )
            return None
        return "".join(fivem_rcon.decoder(r) for r in reponses)

    return envoyer


def _client_actif() -> bool:
    resultat = subprocess.run(
        COMMANDE_PROCESS, capture_output=True, check=False, text=True
    )
    return "True" in (resultat.stdout or "")


def _lancer_client() -> None:
    subprocess.run(COMMANDE_LANCEMENT, capture_output=True, check=False, text=True)


def _fermer_client() -> None:
    subprocess.run(COMMANDE_FERMETURE, capture_output=True, check=False, text=True)


def _pour_windows(chemin: Path) -> str:
    """Chemin lisible par Windows PowerShell (WSL : conversion par wslpath)."""
    if os.name == "nt":
        return str(chemin)
    wslpath = shutil.which("wslpath")
    if wslpath:
        resultat = subprocess.run(
            [wslpath, "-w", str(chemin)], capture_output=True, text=True, check=False
        )
        if resultat.returncode == 0 and resultat.stdout.strip():
            return resultat.stdout.strip()
    return str(chemin)


def _capturer(chemin: Path, etat: EtatCourse) -> int:
    """Capture l'écran, avec au moins 5,5 s entre deux captures."""
    ecart = time.monotonic() - etat.derniere_capture
    if etat.derniere_capture and ecart < ECART_CAPTURES:
        time.sleep(ECART_CAPTURES - ecart)
    resultat = subprocess.run(
        [
            POWERSHELL,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            _pour_windows(SCRIPTS / "capturer-jeu.ps1"),
            "-Sortie",
            _pour_windows(chemin),
        ],
        capture_output=True,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    etat.derniere_capture = time.monotonic()
    return resultat.returncode


def _comparer(premiere: Path, seconde: Path, seuil: float) -> float:
    """Indice SSIM entre les deux captures, configuration sans masque."""
    resultat = comparer_rendu.comparer(
        premiere, seconde, {"largeur": 480, "seuil": seuil}
    )
    return float(resultat["indice"])


def _instant_client() -> dict[str, tuple[int, int]]:
    """Taille et nombre de lignes des journaux client au début de la course."""
    instant: dict[str, tuple[int, int]] = {}
    dossier = journal_client.dossier_journaux()
    for chemin in dossier.glob("CitizenFX_log_*.log"):
        try:
            donnees = chemin.read_bytes()
        except OSError:
            continue
        instant[str(chemin)] = (
            len(donnees),
            len(donnees.decode("utf-8", errors="replace").splitlines()),
        )
    return instant


def _erreurs_client_depuis(instant: dict[str, tuple[int, int]]) -> list[str]:
    """Lignes SCRIPT ERROR ajoutées depuis le début de la course."""
    erreurs: list[str] = []
    dossier = journal_client.dossier_journaux()
    for chemin in dossier.glob("CitizenFX_log_*.log"):
        try:
            texte = chemin.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        lignes = texte.splitlines()
        avant = instant.get(str(chemin))
        if avant is None:
            nouvelles = lignes
        else:
            _, nombre = avant
            nouvelles = lignes[nombre:] if len(lignes) > nombre else []
        for ligne in nouvelles:
            message = journal_client.texte(ligne)
            if "SCRIPT ERROR" in message or "script error" in message:
                erreurs.append(message)
    return erreurs


def _mot_de_passe_conteneur() -> str | None:
    """Lit le mot de passe rcon dans le conteneur (fichier racine sous WSL)."""
    resultat = subprocess.run(
        [
            "docker",
            "compose",
            "-f",
            "docker-compose.yml",
            "-f",
            "docker-compose.dev.yml",
            "exec",
            "-T",
            "fxserver",
            "cat",
            "/opt/fivem/server-data/cache/rcon_password",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    valeur = (resultat.stdout or "").strip()
    return valeur or None


class ContexteReel:
    """Contexte concret, branché sur rcon, Docker, PowerShell et les PNG."""

    def __init__(self, options: dict) -> None:
        mot_de_passe = fivem_rcon.lire_mot_de_passe(
            fivem_rcon.FICHIER_MOT_DE_PASSE, dict(os.environ)
        )
        if not mot_de_passe:
            mot_de_passe = _mot_de_passe_conteneur()
        if not mot_de_passe:
            raise PrerequisManquant(
                f"Mot de passe rcon introuvable ({fivem_rcon.FICHIER_MOT_DE_PASSE}). "
                "rcon n'est actif qu'avec la surcouche dev et TXADMIN=false."
            )
        self.envoyer_rcon = _envoyer_rcon_reel(
            "127.0.0.1", 30120, mot_de_passe, min(5.0, options["delai"])
        )
        self.lire_journal = _lire_journal_commandes
        self.instant_client = self._instant_client
        self.client_actif = _client_actif
        self.lancer_client = _lancer_client
        self.fermer_client = _fermer_client
        self.dormir = time.sleep
        self.etat = EtatCourse()
        self.erreurs_client = lambda: _erreurs_client_depuis(self.etat.debut_client)
        self.capturer = lambda destination: _capturer(destination, self.etat)
        self.comparer = lambda premiere, seconde: _comparer(
            premiere, seconde, options["seuil"]
        )

    def _instant_client(self) -> dict[str, tuple[int, int]]:
        """Relève les journaux client au début de la course et retient l'instant."""
        instant = _instant_client()
        self.etat.debut_client = instant
        return instant


def _attendre(
    texte: str, contexte, etat: EtatCourse, delai: float, indice: str
) -> None:
    """Attend une ligne du journal apparue depuis le début de la course."""
    echeance = time.monotonic() + delai
    while True:
        lignes = contexte.lire_journal()[etat.debut_journal :]
        for ligne in lignes:
            if "etat=refus" in ligne or "etat=echec" in ligne:
                raise ControleEchoue(f"Rapport de la passerelle : {ligne.strip()}")
            if texte in ligne:
                return
        if time.monotonic() >= echeance:
            raise PrerequisManquant(
                f"Délai de {delai:g} s dépassé en attendant {texte!r}. {indice}"
            )
        contexte.dormir(min(INTERVALLE_JOURNAL, max(0.0, echeance - time.monotonic())))


def _commande(contexte, texte: str) -> None:
    """Envoie une commande rcon et signale une réponse injoignable."""
    reponse = contexte.envoyer_rcon(texte)
    if reponse is None or fivem_rcon.refus(reponse):
        raise PrerequisManquant(
            f"rcon injoignable ou refusé pour {texte!r} : {str(reponse).strip()}. "
            "Vérifie le serveur de développement et le mot de passe rcon."
        )


def _ligne_open(page: str) -> str:
    return f"[gf_testbridge] page={page} action=open etat=ouvert"


def _ligne_close(page: str) -> str:
    return f"[gf_testbridge] page={page} action=close etat=ferme calques=0"


def _test_page(
    page: str, contexte, options: dict, etat: EtatCourse, dossier: Path
) -> Verdict:
    """Ouvre, capture, ferme, capture et compare une page."""
    verdict = Verdict(page=page)
    etat.pages_ouvertes.append(page)
    _commande(contexte, f"gf_bridge open {page}")
    _attendre(
        _ligne_open(page),
        contexte,
        etat,
        options["delai"],
        f"Vérifie que la passerelle connaît la page {page} et que son NUI se charge.",
    )
    verdict.ouvert = True
    contexte.dormir(DORMIR_OUVERTURE)
    ouvert = dossier / f"{page}-ouvert.png"
    if contexte.capturer(ouvert) != 0:
        raise ControleEchoue(
            f"Capture impossible : {ouvert}. Vérifie que le client FiveM a une fenêtre, "
            "et que la capture n'est pas trop proche de la précédente (5 s minimum)."
        )

    _commande(contexte, f"gf_bridge close {page}")
    _attendre(
        _ligne_close(page),
        contexte,
        etat,
        options["delai"],
        f"Vérifie que la passerelle a bien fermé tous les calques de {page}.",
    )
    verdict.ferme = True
    etat.pages_ouvertes.remove(page)
    contexte.dormir(max(0.0, ECART_CAPTURES - DORMIR_OUVERTURE))
    ferme = dossier / f"{page}-ferme.png"
    if contexte.capturer(ferme) != 0:
        raise ControleEchoue(
            f"Capture impossible : {ferme}. Vérifie la fenêtre du client et l'écart de 5 s."
        )
    try:
        verdict.indice = contexte.comparer(ouvert, ferme)
    except (ValueError, OSError) as exc:
        raise ControleEchoue(
            f"Comparaison impossible entre {ouvert.name} et {ferme.name} : {exc}"
        ) from None
    if verdict.indice >= options["seuil"]:
        raise ControleEchoue(
            f"La page {page} n'a pas modifié le rendu : SSIM {verdict.indice:.4f} "
            f">= seuil {options['seuil']:.4f}. Vérifie l'ouverture du NUI et les calques."
        )
    verdict.reussi = True
    verdict.detail = f"SSIM {verdict.indice:.4f} < {options['seuil']:.4f}"
    return verdict


def _nettoyer(contexte, options: dict, etat: EtatCourse) -> None:
    """Ferme les pages encore ouvertes, la passerelle et le client lancé ici."""
    if not etat.debut_journal and not etat.pages_ouvertes and not etat.client_lance:
        return
    for page in list(etat.pages_ouvertes):
        try:
            _commande(contexte, f"gf_bridge close {page}")
        except PrerequisManquant:
            pass
    try:
        _commande(contexte, "stop gf_testbridge")
    except PrerequisManquant:
        pass
    if etat.client_lance and not options["garder_client"]:
        try:
            contexte.fermer_client()
        except OSError as exc:
            print(f"fermeture du client impossible : {exc}", file=sys.stderr)


def _resume(etat: EtatCourse, dossier: Path) -> None:
    """Affiche le tableau des verdicts et le dossier des captures."""
    print("\nRésultats NUI")
    for verdict in etat.verdicts:
        indice = f"{verdict.indice:.4f}" if verdict.indice is not None else "—"
        statut = "OK" if verdict.reussi else "ÉCHEC"
        ouvert = "oui" if verdict.ouvert else "non"
        ferme = "oui" if verdict.ferme else "non"
        print(
            f"  {verdict.page:<16} ouvert={ouvert:<3} fermé={ferme:<3} "
            f"SSIM={indice:<7} {statut}"
        )
        if verdict.detail and not verdict.reussi:
            print(f"      {verdict.detail}")
    for erreur in etat.erreurs:
        print(f"  ERREUR {erreur}")
    print(f"Captures : {dossier}")


def executer(
    contexte, pages: list[str], options: dict, sortie: Path
) -> int:
    """Joue le test NUI et renvoie 0, 1 ou 2. Tout est injectable."""
    etat = EtatCourse()
    code = 0
    dossier = sortie
    try:
        dossier = valider_sortie(sortie, options.get("racine", RACINE))
        valider_pages(pages)
        dossier.mkdir(parents=True, exist_ok=True)
        etat.debut_journal = len(contexte.lire_journal())
        etat.debut_client = (
            contexte.instant_client()
            if hasattr(contexte, "instant_client")
            else _instant_client()
        )
        _commande(contexte, "stop gf_testbridge")
        _commande(contexte, "ensure gf_testbridge")

        pret = False
        echeance = time.monotonic() + options["delai"]
        while True:
            lignes = contexte.lire_journal()[etat.debut_journal :]
            if any(LIGNE_DESACTIVE in ligne for ligne in lignes):
                raise PrerequisManquant(
                    "gf_testbridge est désactivé : active la ressource dans la "
                    "configuration de développement avant de relancer le pilote."
                )
            if any(LIGNE_PRET in ligne for ligne in lignes):
                pret = True
                break
            if time.monotonic() >= echeance:
                raise PrerequisManquant(
                    f"Délai de {options['delai']:g} s dépassé : ligne "
                    f"{LIGNE_PRET!r} absente du journal. Vérifie le chargement "
                    "de gf_testbridge."
                )
            contexte.dormir(INTERVALLE_JOURNAL)

        if not contexte.client_actif():
            if options["sans_client"]:
                raise PrerequisManquant(
                    "Aucun client FiveM détecté et --sans-client est actif : "
                    "lance le client puis relance le pilote sans --sans-client."
                )
            contexte.lancer_client()
            etat.client_lance = True

        _attendre(
            LIGNE_CLIENT,
            contexte,
            etat,
            options["delai"],
            "Le client n'a pas signalé sa présence : est-il connecté au serveur "
            "127.0.0.1:30120 ?",
        )

        for page in pages:
            verdict = _test_page(page, contexte, options, etat, dossier)
            etat.verdicts.append(verdict)

        lignes = contexte.lire_journal()[etat.debut_journal :]
        for ligne in lignes:
            if any(motif in ligne for motif in MOTIFS_ERREUR):
                etat.erreurs.append(f"serveur : {ligne.strip()}")
        for ligne in contexte.erreurs_client():
            etat.erreurs.append(f"client : {ligne}")
        if etat.erreurs:
            code = 1
    except PrerequisManquant as exc:
        print(f"Prérequis manquant : {exc}", file=sys.stderr)
        code = 2
    except ControleEchoue as exc:
        print(f"Contrôle en échec : {exc}", file=sys.stderr)
        code = 1
    except OSError as exc:
        print(f"Prérequis manquant : {exc}", file=sys.stderr)
        code = 2
    finally:
        _nettoyer(contexte, options, etat)
        _resume(etat, dossier)
    return code


class _Analyseur(argparse.ArgumentParser):
    """Analyseur d'arguments avec des messages d'erreur en français."""

    def error(self, message: str) -> None:
        traductions = (
            ("the following arguments are required:", "arguments requis manquants :"),
            ("unrecognized arguments:", "arguments non reconnus :"),
            ("invalid float value:", "nombre invalide :"),
        )
        for anglais, francais in traductions:
            if message.startswith(anglais):
                message = francais + message[len(anglais) :]
                break
        print(f"Erreur : {message}", file=sys.stderr)
        self.print_usage(sys.stderr)
        raise SystemExit(2)


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée CLI : construit le contexte réel puis appelle executer."""
    analyseur = _Analyseur(description=__doc__.split("\n\n")[0])
    analyseur.add_argument("--pages", nargs="+", default=list(PAGES_DEFAUT))
    horodatage = datetime.now().strftime("%Y%m%d-%H%M%S")
    analyseur.add_argument(
        "--sortie",
        type=Path,
        default=Path(os.environ.get("TEMP", "/tmp")) / "gf-nui" / horodatage,
    )
    analyseur.add_argument("--sans-client", action="store_true")
    analyseur.add_argument("--garder-client", action="store_true")
    analyseur.add_argument("--seuil", type=float, default=SEUIL_DEFAUT)
    analyseur.add_argument("--delai", type=float, default=DELAI_DEFAUT)
    analyseur.add_argument("--verbeux", action="store_true")
    args = analyseur.parse_args(argv)

    if args.seuil < 0 or args.seuil > 1:
        print("Erreur : --seuil doit être compris entre 0 et 1.", file=sys.stderr)
        return 2
    if args.delai <= 0:
        print("Erreur : --delai doit être strictement positif.", file=sys.stderr)
        return 2
    try:
        valider_pages(args.pages)
        options = {
            "sans_client": args.sans_client,
            "garder_client": args.garder_client,
            "seuil": args.seuil,
            "delai": args.delai,
            "verbeux": args.verbeux,
            "racine": RACINE,
        }
        valider_sortie(args.sortie, RACINE)
        contexte = ContexteReel(options)
    except PrerequisManquant as exc:
        print(f"Prérequis manquant : {exc}", file=sys.stderr)
        return 2
    return executer(contexte, args.pages, options, args.sortie)


if __name__ == "__main__":
    sys.exit(main())
