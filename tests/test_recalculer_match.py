"""Tests du recalcul des classements à partir du journal gf_journal.

Règles testées (identiques à celles du script et du code serveur) :

* une ligne `kill` compte une mort (même hors phase `live`, même sans tueur) ;
* une ligne `kill` avec `tueur` = objet crédite un kill, `tueur` = false n'en
  crédite aucun (`gf:modeKill` dans gf_stats, AttackRules.mort, handler
  gf:playerKilled de gf_redzone) ;
* les lignes `mort` ne comptent pas : elles ne font que nommer ;
* la liste `joueurs` de `debut_match` fournit le roster initial, y compris les
  joueurs à 0 kill / 0 mort sans autre ligne (`gf:matchStarted`) ;
* les lignes `arrivee` avant-match ont un `match_id` null et ne sont pas
  sélectionnées pour le match ;
* en Attaque, un joueur parti pendant le match reste au classement, tri
  kills desc / deaths asc / nom asc, comparé strictement (sendMatchResults) ;
* en Redzone, un joueur parti avant la fin est exclu, tri kills desc / deaths
  asc avec repli par nom (ranking), mais l'ordre interne d'un groupe
  d'égalité kills+deaths est libre et ignoré à la comparaison ;
* la ligne `resultats` sert uniquement de référence de comparaison.

Aucun sous-processus, ni réseau, ni base : le module est chargé par chemin.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "recalculer_match.py"


def charger_module() -> ModuleType:
    """Charge scripts/recalculer_match.py sans passer par un sous-processus."""
    spec = importlib.util.spec_from_file_location("recalculer_match", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("module recalculer_match introuvable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


M = charger_module()


def joueur(src: int, lic: str, nom: str) -> dict:
    """Joueur au format des lignes gf_journal."""
    return {"src": src, "id": f"license:{lic}", "nom": nom}


ALICE = joueur(1, "alice", "Alice")
BOB = joueur(2, "bob", "Bob")
CLEM = joueur(3, "clem", "Clem")
DANI = joueur(4, "dani", "Dani")
EVE = joueur(5, "eve", "Eve")


def ligne(
    match: str | None,
    type_evenement: str,
    mode: str,
    **donnees: object,
) -> str:
    """Construit une ligne JSON du journal (`match_id` null autorisé)."""
    return json.dumps(
        {
            "id": 1,
            "match_id": match,
            "mode": mode,
            "manche": 1,
            "t_ms": 1000,
            "type": type_evenement,
            "donnees": donnees,
        },
        ensure_ascii=False,
    )


def roster(entrees: list[tuple[dict, str | None]]) -> list[dict]:
    """Liste `joueurs` d'une ligne `debut_match` (joueur + équipe optionnelle)."""
    return [{"joueur": joueur_obj, "equipe": equipe} for joueur_obj, equipe in entrees]


def journal_attack(avec_dernier_kill: bool = True) -> str:
    """Match Attaque réaliste reconstruit depuis le roster du coup d'envoi.

    Les `arrivee` sont avant-match (match_id null) et ne sont donc pas
    sélectionnées ; `debut_match` porte le roster complet avec les équipes, y
    compris Eve qui n'a aucune autre ligne. Alice : 1 kill (sur Bob), 2 morts ;
    Bob : 1 kill (sur Alice), 2 morts ; Clem : 1 kill (sur Bob), 1 mort ;
    Dani : 1 kill (sur Clem), 0 mort, puis départ pendant le match ;
    Eve : 0 kill / 0 mort (uniquement dans `debut_match.joueurs`).
    Tri attendu (kills desc, deaths asc, nom asc) :
    Dani (1/0), Clem (1/1), Alice (1/2), Bob (1/2), Eve (0/0).
    """
    lignes = [
        # Arrivées avant le début du match : match_id null, non sélectionnées.
        ligne(None, "arrivee", "attack", joueur=ALICE, equipe="A"),
        ligne(None, "arrivee", "attack", joueur=BOB, equipe="B"),
        ligne(None, "arrivee", "attack", joueur=CLEM, equipe="A"),
        ligne(None, "arrivee", "attack", joueur=DANI, equipe="B"),
        ligne(
            "atk-1",
            "debut_match",
            "attack",
            map="de_lagoon",
            joueurs=roster(
                [
                    (ALICE, "A"),
                    (BOB, "B"),
                    (CLEM, "A"),
                    (DANI, "B"),
                    (EVE, "A"),
                ]
            ),
        ),
        # Bob tue Alice : kill crédité pour Bob.
        ligne(
            "atk-1", "mort", "attack", victime=ALICE, tueur=BOB, arme="weapon_pistol"
        ),
        ligne(
            "atk-1",
            "kill",
            "attack",
            victime=ALICE,
            tueur=BOB,
            equipe_victime="A",
            equipe_tueur="B",
        ),
        # Alice tue Bob : kill crédité pour Alice.
        ligne("atk-1", "mort", "attack", victime=BOB, tueur=ALICE, arme="weapon_rifle"),
        ligne(
            "atk-1",
            "kill",
            "attack",
            victime=BOB,
            tueur=ALICE,
            equipe_victime="B",
            equipe_tueur="A",
        ),
        # Clem tue Bob : kill crédité pour Clem.
        ligne("atk-1", "mort", "attack", victime=BOB, tueur=CLEM, arme="weapon_rifle"),
        ligne(
            "atk-1",
            "kill",
            "attack",
            victime=BOB,
            tueur=CLEM,
            equipe_victime="B",
            equipe_tueur="A",
        ),
        # Alice meurt sans tueur crédité : une mort, aucun kill.
        ligne("atk-1", "mort", "attack", victime=ALICE, tueur=False, arme="fall"),
        ligne(
            "atk-1",
            "kill",
            "attack",
            victime=ALICE,
            tueur=False,
            equipe_victime="A",
            equipe_tueur=None,
        ),
    ]
    if avec_dernier_kill:
        # Dani tue Clem, puis Dani quitte pendant le match : il reste classé.
        lignes += [
            ligne(
                "atk-1", "mort", "attack", victime=CLEM, tueur=DANI, arme="weapon_smg"
            ),
            ligne(
                "atk-1",
                "kill",
                "attack",
                victime=CLEM,
                tueur=DANI,
                equipe_victime="A",
                equipe_tueur="B",
            ),
            ligne("atk-1", "depart", "attack", joueur=DANI, equipe="B"),
        ]
    lignes.append(
        ligne(
            "atk-1",
            "resultats",
            "attack",
            rows=[
                {"name": "Dani", "team": "B", "kills": 1, "deaths": 0},
                {"name": "Clem", "team": "A", "kills": 1, "deaths": 1},
                {"name": "Alice", "team": "A", "kills": 1, "deaths": 2},
                {"name": "Bob", "team": "B", "kills": 1, "deaths": 2},
                {"name": "Eve", "team": "A", "kills": 0, "deaths": 0},
            ],
        )
    )
    return "\n".join(lignes) + "\n"


def journal_redzone(ordre_resultats: list[str] | None = None) -> str:
    """Match Redzone réaliste avec une égalité kills+deaths à ordre libre.

    Les `arrivee` sont avant-match (match_id null) ; `debut_match` porte le
    roster, dont Eve (0/0) qui n'a aucune autre ligne. Alice, Bob et Clem sont
    à 1 kill / 1 mort ; Dani part avant la fin et est exclu. Les lignes
    `resultats` inversent l'ordre par nom du groupe d'égalité : ranking()
    utilise `table.sort` instable, l'ordre interne du groupe est donc libre et
    ne doit pas produire d'écart.

    `ordre_resultats` permet de remplacer l'ordre des lignes de référence
    (utilisé pour tester une inversion entre deux groupes distincts).
    """
    lignes = [
        ligne(None, "arrivee", "redzone", joueur=ALICE),
        ligne(None, "arrivee", "redzone", joueur=BOB),
        ligne(None, "arrivee", "redzone", joueur=CLEM),
        ligne(None, "arrivee", "redzone", joueur=DANI),
        ligne(
            "rz-1",
            "debut_match",
            "redzone",
            map="de_scrapyard",
            joueurs=roster(
                [
                    (ALICE, None),
                    (BOB, None),
                    (CLEM, None),
                    (DANI, None),
                    (EVE, None),
                ]
            ),
        ),
        # Alice tue Bob : Alice 1/0, Bob 0/1.
        ligne(
            "rz-1", "mort", "redzone", victime=BOB, tueur=ALICE, arme="weapon_pistol"
        ),
        ligne("rz-1", "kill", "redzone", victime=BOB, tueur=ALICE),
        # Clem tue Alice : Clem 1/0, Alice 1/1.
        ligne(
            "rz-1", "mort", "redzone", victime=ALICE, tueur=CLEM, arme="weapon_rifle"
        ),
        ligne("rz-1", "kill", "redzone", victime=ALICE, tueur=CLEM),
        # Clem meurt sans tueur crédité : Clem 1/1.
        ligne("rz-1", "mort", "redzone", victime=CLEM, tueur=False, arme="fall"),
        ligne("rz-1", "kill", "redzone", victime=CLEM, tueur=False),
        # Bob tue Dani : Bob 1/1, Dani 0/1 (Dani part ensuite, exclu).
        ligne("rz-1", "mort", "redzone", victime=DANI, tueur=BOB, arme="weapon_smg"),
        ligne("rz-1", "kill", "redzone", victime=DANI, tueur=BOB),
        # Dani part avant la fin : endGame ne classe pas les joueurs partis.
        ligne("rz-1", "depart", "redzone", joueur=DANI),
    ]
    comptes = {
        "Alice": {"name": "Alice", "kills": 1, "deaths": 1},
        "Bob": {"name": "Bob", "kills": 1, "deaths": 1},
        "Clem": {"name": "Clem", "kills": 1, "deaths": 1},
        "Eve": {"name": "Eve", "kills": 0, "deaths": 0},
    }
    noms = ordre_resultats or ["Clem", "Alice", "Bob", "Eve"]
    lignes.append(
        ligne(
            "rz-1",
            "resultats",
            "redzone",
            rows=[comptes[nom] for nom in noms],
        )
    )
    return "\n".join(lignes) + "\n"


def ecrire_et_executer(texte: str, args: list[str]) -> tuple[int, str, str]:
    """Écrit le journal dans un dossier temporaire et exécute main()."""
    with tempfile.TemporaryDirectory() as dossier:
        chemin = Path(dossier) / "journal.jsonl"
        chemin.write_text(texte, encoding="utf-8")
        sortie, erreurs = io.StringIO(), io.StringIO()
        with (
            contextlib.redirect_stdout(sortie),
            contextlib.redirect_stderr(erreurs),
        ):
            code = M.main([str(chemin), *args])
    return code, sortie.getvalue(), erreurs.getvalue()


class RecalculAttaque(unittest.TestCase):
    """Le classement Attaque est reconstruit depuis le roster et les `kill`."""

    def test_match_attack_complet_est_identique(self) -> None:
        code, sortie, _ = ecrire_et_executer(
            journal_attack(), ["--match", "atk-1"]
        )
        self.assertEqual(M.SORTIE_IDENTIQUE, code)
        self.assertIn("Écarts : aucun", sortie)
        self.assertIn("Eve : 0 kill(s), 0 mort(s)", sortie)
        self.assertNotIn("license:", sortie)

    def test_joueur_uniquement_au_coup_d_envoi_est_present(self) -> None:
        """Eve, absente de `arrivee`/`kill`, vient bien de `debut_match`."""
        table, mode = M.recalculer(
            [
                {
                    "match_id": "atk-1",
                    "mode": "attack",
                    "type": "debut_match",
                    "donnees": {"joueurs": [{"joueur": EVE, "equipe": "A"}]},
                }
            ]
        )
        self.assertEqual("attack", mode)
        self.assertEqual(
            [{"nom": "Eve", "kills": 0, "deaths": 0, "team": "A"}], table
        )

    def test_un_kill_retire_donne_un_ecart(self) -> None:
        """Sans le kill de Dani sur Clem, la référence ne correspond plus."""
        code, sortie, _ = ecrire_et_executer(
            journal_attack(avec_dernier_kill=False), ["--match", "atk-1"]
        )
        self.assertEqual(M.SORTIE_ECART, code)
        self.assertIn("Écarts :", sortie)


class RecalculRedzone(unittest.TestCase):
    """Le classement Redzone ignore l'ordre interne des groupes d'égalité."""

    def test_match_redzone_complet_est_identique(self) -> None:
        """L'égalité 1/1 est dans l'ordre inverse du repli par nom : code 0."""
        code, sortie, _ = ecrire_et_executer(journal_redzone(), [])
        self.assertEqual(M.SORTIE_IDENTIQUE, code)
        self.assertIn("Écarts : aucun", sortie)
        self.assertIn("Eve : 0 kill(s), 0 mort(s)", sortie)

    def test_inversion_entre_groupes_donne_un_ecart(self) -> None:
        """Un 0/0 avant les 1/1 inverse deux groupes : code 1."""
        code, sortie, _ = ecrire_et_executer(
            journal_redzone(ordre_resultats=["Eve", "Alice", "Bob", "Clem"]), []
        )
        self.assertEqual(M.SORTIE_ECART, code)
        self.assertIn("Groupe 1", sortie)
        self.assertIn("kills=0", sortie)

    def test_ligne_sans_match_id_est_ignoree(self) -> None:
        """Une arrivée avant-match (match_id null) ne bloque pas la sélection."""
        code, sortie, _ = ecrire_et_executer(journal_redzone(), [])
        self.assertEqual(M.SORTIE_IDENTIQUE, code)
        self.assertIn("Match rz-1", sortie)


class Erreurs(unittest.TestCase):
    """Les données illisibles et les matches absents donnent le code 2."""

    def test_json_illisible(self) -> None:
        code, _, erreurs = ecrire_et_executer("{\"match_id\": ", [])
        self.assertEqual(M.SORTIE_ILLISIBLE, code)
        self.assertIn("JSON illisible", erreurs)

    def test_match_introuvable(self) -> None:
        code, _, erreurs = ecrire_et_executer(
            journal_attack(), ["--match", "inconnu"]
        )
        self.assertEqual(M.SORTIE_ILLISIBLE, code)
        self.assertIn("match introuvable", erreurs)


if __name__ == "__main__":
    unittest.main()
