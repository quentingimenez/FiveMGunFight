#!/usr/bin/env python3
"""Envoie une commande à la console du serveur de développement (rcon).

Sert surtout à recharger une ressource après une modification, sans recréer
le conteneur ni relancer le client FiveM :

  python scripts/fivem_rcon.py restart gf_lobby
  python scripts/fivem_rcon.py ensure gf_redzone
  python scripts/fivem_rcon.py status

rcon n'existe qu'en développement et en mode direct : la surcouche
docker-compose.dev.yml fixe GF_DEV_RCON=true et, si TXADMIN=false,
docker/entrypoint.sh tire un mot de passe aléatoire à chaque démarrage. Il est
écrit dans server-data/cache/rcon_password (ignoré par git) et lu ici. La
variable GF_RCON_PASSWORD le remplace si elle est définie.

Codes de sortie : 0 réponse reçue, 1 pas de réponse, 2 mot de passe absent ou refusé.
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
FICHIER_MOT_DE_PASSE = RACINE / "server-data" / "cache" / "rcon_password"
EN_TETE = b"\xff\xff\xff\xff"


def paquet(mot_de_passe: str, commande: str) -> bytes:
    """Datagramme rcon de FXServer : 4 octets 0xFF, « rcon <mdp> <commande> »."""
    if not mot_de_passe or any(c.isspace() for c in mot_de_passe):
        raise ValueError("mot de passe rcon vide ou avec un espace")
    if "\n" in commande or "\r" in commande:
        raise ValueError("une seule commande, sans retour à la ligne")
    return EN_TETE + f"rcon {mot_de_passe} {commande}".encode()


def decoder(reponse: bytes) -> str:
    """Texte d'une réponse rcon, sans l'en-tête « 0xFF x4 print »."""
    prefixe = EN_TETE + b"print "
    reponse = reponse.removeprefix(prefixe)
    return reponse.decode("utf-8", errors="replace")


# Réponses de FXServer qui refusent la commande (outofbandhandlers/RconOutOfBand.h).
REFUS = ("Invalid password.", "The server must set rcon_password")


def refus(texte: str) -> bool:
    return texte.startswith(REFUS)


def lire_mot_de_passe(fichier: Path, environnement: dict[str, str]) -> str | None:
    if environnement.get("GF_RCON_PASSWORD"):
        return environnement["GF_RCON_PASSWORD"]
    try:
        return fichier.read_text(encoding="utf-8").strip() or None
    except OSError:
        return None


def envoyer(hote: str, port: int, donnees: bytes, delai: float) -> list[bytes]:
    """Envoie le datagramme et rassemble les réponses jusqu'au silence."""
    reponses: list[bytes] = []
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(delai)
        sock.sendto(donnees, (hote, port))
        try:
            while True:
                reponse, _ = sock.recvfrom(65535)
                reponses.append(reponse)
                sock.settimeout(0.5)
        except TimeoutError:
            pass
    return reponses


def main(argv: list[str] | None = None) -> int:
    analyseur = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    analyseur.add_argument("commande", nargs="+", help="commande console, ex. restart gf_lobby")
    analyseur.add_argument("--hote", default="127.0.0.1")
    analyseur.add_argument("--port", type=int, default=30120)
    analyseur.add_argument("--delai", type=float, default=5.0, help="attente de la réponse (s)")
    analyseur.add_argument("--fichier", type=Path, default=FICHIER_MOT_DE_PASSE)
    args = analyseur.parse_args(argv)

    mot_de_passe = lire_mot_de_passe(args.fichier, dict(os.environ))
    if not mot_de_passe:
        print(
            f"Mot de passe rcon introuvable ({args.fichier}).\n"
            "rcon n'est actif qu'avec la surcouche docker-compose.dev.yml et TXADMIN=false :\n"
            "recrée le conteneur comme indiqué dans docs/debug-test.md § 2.",
            file=sys.stderr,
        )
        return 2

    reponses = envoyer(args.hote, args.port, paquet(mot_de_passe, " ".join(args.commande)), args.delai)
    if not reponses:
        print(
            f"Aucune réponse de {args.hote}:{args.port} en {args.delai} s : serveur arrêté, "
            "ou conteneur démarré avant l'activation de rcon (recrée-le).",
            file=sys.stderr,
        )
        return 1
    texte = "".join(decoder(r) for r in reponses)
    if refus(texte):
        print(
            f"{texte.strip()}\nLe mot de passe ne correspond pas au conteneur en cours : "
            "recrée-le avec la surcouche dev et TXADMIN=false (docs/debug-test.md § 2).",
            file=sys.stderr,
        )
        return 2
    print(texte, end="" if texte.endswith("\n") else "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
