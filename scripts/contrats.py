#!/usr/bin/env python3
"""Extrait et vérifie le registre des contrats entre ressources FiveMGunFight.

Le registre est décrit par un `contrat.json` par ressource démarrée dans
`server-data/server.cfg`. Chaque contrat est extrait du code Lua de la
ressource (commentaires retirés) et de son `fxmanifest.lua` : exports fournis
et consommés, événements émis et écoutés, state bags écrits et lus,
dépendances dures et optionnelles. La dette technique connue (dépendances
cachées et cycles de longueur deux) est calculée à partir de l'extraction.

Trois modes, mutuellement exclusifs ; --verifier est le défaut :

  python scripts/contrats.py --initialiser   écrit les contrat.json
  python scripts/contrats.py --doc           génère docs/contrats.md
  python scripts/contrats.py --verifier      vérifie code, registre et doc

Codes de sortie : 0 si tout est conforme, 1 si des écarts ou des écritures
impossibles sont constatés, 2 si une ressource ou un manifeste manque, si un
contrat est absent/invalide en mode --doc ou si les arguments sont incorrects.

Limite connue : l'extraction est lexicale. Un export appelé à travers une
variable (`local inv = exports.gf_inventory` puis `inv:Fonction()`) n'est pas
vu comme consommé ; seule la dépendance optionnelle (`GetResourceState`) l'est.
Écrire `exports.gf_x:Fonction()` directement rend le lien vérifiable.

Toutes les fonctions d'extraction sont pures et acceptent de petites chaînes
Lua arbitraires : elles ne lisent aucun fichier et n'ont aucun effet de bord.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]

CLES_CONTRAT = (
    "ressource",
    "exports",
    "consomme",
    "emet",
    "ecoute",
    "state_bags",
    "dependances",
    "dette",
)
CLES_LISTES = ("exports", "consomme", "emet", "ecoute")

MOTIF_ENSURE = re.compile(r"^\s*ensure\s+(gf_\w+)\s*$", re.MULTILINE)
MOTIF_COMMENTAIRE_BLOC = re.compile(r"--\[\[.*?\]\]", re.DOTALL)
MOTIF_COMMENTAIRE_LIGNE = re.compile(r"--[^\n]*")

CHAINE = r"""(['"])(.*?)\1"""
MOTIF_EXPORT_FOURNI = re.compile(rf"\bexports\s*\(\s*{CHAINE}")
MOTIF_EXPORT_DOT = re.compile(r"\bexports\s*\.\s*(gf_\w+)\s*\.\s*([A-Za-z_]\w*)")
MOTIF_EXPORT_BRACKET = re.compile(
    r"\bexports\s*\[\s*['\"](gf_\w+)['\"]\s*\]\s*:\s*([A-Za-z_]\w*)"
)
MOTIF_EXPORT_COLON = re.compile(r"\bexports\s*\.\s*(gf_\w+)\s*:\s*([A-Za-z_]\w*)")

MOTIF_EMETTEUR = re.compile(
    rf"\b(?:TriggerEvent|TriggerServerEvent|TriggerClientEvent)\s*\(\s*{CHAINE}"
)
MOTIF_ECOUTEUR = re.compile(
    rf"\b(?:AddEventHandler|RegisterNetEvent)\s*\(\s*{CHAINE}"
)
NOM_RESSOURCE = r"gf_[A-Za-z0-9_]+"

# `.state:set(...)`, mais aussi une variable locale (`local state = Player(src).state`,
# puis `state:set('gf_mode', ...)`) : gf_core écrit gf_mode ainsi.
MOTIF_SET_STATE = re.compile(rf"\b\w*state\s*:\s*set\s*\(\s*{CHAINE}", re.IGNORECASE)
MOTIF_SET_GLOBAL = re.compile(rf"\bGlobalState\s*:\s*set\s*\(\s*{CHAINE}")
MOTIF_ECRITURE_DIRECTE = re.compile(
    rf"(?:\.state|GlobalState)\s*\.\s*(gf_\w+)\s*=(?!=)"
)
MOTIF_LECTURE_STATE = re.compile(
    rf"(?:\.state|GlobalState)\s*\.\s*(gf_\w+)\b(?!\s*=(?!=))"
)

MOTIF_GET_RESOURCE_STATE = re.compile(rf"\bGetResourceState\s*\(\s*{CHAINE}")

MOTIF_BLOC_DEPENDANCES = re.compile(r"\bdependencies\s*\{([^{}]*)\}", re.DOTALL)
MOTIF_DEPENDANCE_SEULE = re.compile(rf"\bdependency\s+{CHAINE}")
MOTIF_CHAINE_LITTERALE = re.compile(CHAINE)


def sans_commentaires(texte: str) -> str:
    """Retire les commentaires Lua (blocs `--[[ ]]` et lignes `--`) d'un texte.

    Les chaînes ne sont pas interprétées : comme dans `tests/test_evenements.py`,
    les blocs sont retirés avant les commentaires de ligne. La fonction est
    pure et ne modifie pas le texte reçu.
    """
    texte = MOTIF_COMMENTAIRE_BLOC.sub("", texte)
    return MOTIF_COMMENTAIRE_LIGNE.sub("", texte)


def _trier(valeurs: object) -> list[str]:
    """Renvoie une liste triée de textes sans doublon."""
    return sorted({str(valeur) for valeur in valeurs})


def extraire_exports(texte: str) -> list[str]:
    """Exports fournis par la ressource : noms littéraux de `exports('Nom', ...)`.

    Les commentaires sont retirés avant l'extraction et les appels dynamiques
    sont ignorés. Liste triée sans doublon.
    """
    propre = sans_commentaires(texte)
    return _trier(trouve.group(2) for trouve in MOTIF_EXPORT_FOURNI.finditer(propre))


def extraire_consommes(texte: str, ressource: str) -> list[str]:
    """Exports consommés chez d'autres ressources, notés `'gf_x:Nom'`.

    Trois formes prises en charge : `exports.gf_x:Nom`, `exports.gf_x.Nom` et
    `exports['gf_x']:Nom`. La ressource courante est exclue. Les alias locaux
    (`local core = exports.gf_x`) ne sont pas résolus : hors spécification.
    Liste triée sans doublon.
    """
    propre = sans_commentaires(texte)
    trouves: list[str] = []
    for motif in (MOTIF_EXPORT_COLON, MOTIF_EXPORT_DOT, MOTIF_EXPORT_BRACKET):
        for trouve in motif.finditer(propre):
            cible, nom = trouve.group(1), trouve.group(2)
            if cible != ressource:
                trouves.append(f"{cible}:{nom}")
    return _trier(trouves)


def _est_evenement_concerne(nom: str, ressource: str) -> bool:
    """Dit si un nom d'événement appartient au contrat de la ressource.

    `gf:*` est toujours gardé (avec un suffixe non vide). `gf_x:*` est gardé
    seulement si `gf_x` est un nom de ressource valide différent de la
    ressource courante : les événements du propre préfixe de la ressource ne
    font donc pas partie de son contrat. Les noms construits dynamiquement
    (`'gf_lobby:' .. kind`) ont un suffixe vide et sont ignorés.
    """
    if ":" not in nom:
        return False
    prefixe, suffixe = nom.split(":", 1)
    if not suffixe:
        return False
    if prefixe == "gf":
        return True
    if not re.fullmatch(NOM_RESSOURCE, prefixe):
        return False
    return prefixe != ressource


def extraire_evenements_emis(texte: str, ressource: str) -> list[str]:
    """Événements émis vers `gf:*` ou vers d'autres ressources `gf_x:*`.

    Uniquement `TriggerEvent`, `TriggerServerEvent` et `TriggerClientEvent`
    dont le premier argument est un littéral. Les noms construits dynamiquement
    sont ignorés. Liste triée sans doublon.
    """
    propre = sans_commentaires(texte)
    return _trier(
        trouve.group(2)
        for trouve in MOTIF_EMETTEUR.finditer(propre)
        if _est_evenement_concerne(trouve.group(2), ressource)
    )


def extraire_evenements_ecoutes(texte: str, ressource: str) -> list[str]:
    """Événements écoutés par `AddEventHandler` et `RegisterNetEvent`.

    Mêmes règles de préfixe que `extraire_evenements_emis` : `gf:*` toujours,
    `gf_x:*` seulement pour une autre ressource. Les noms dynamiques sont
    ignorés. Liste triée sans doublon.
    """
    propre = sans_commentaires(texte)
    return _trier(
        trouve.group(2)
        for trouve in MOTIF_ECOUTEUR.finditer(propre)
        if _est_evenement_concerne(trouve.group(2), ressource)
    )


def extraire_state_bags(texte: str) -> dict:
    """State bags écrits et lus (clés commençant par `gf_`).

    Écritures : `:set('gf_...')` sur un `.state`, `GlobalState:set('gf_...')`,
    et affectations directes `.state.gf_... =` / `GlobalState.gf_... =`.
    Lectures : occurrences de lecture de `.state.gf_...` / `GlobalState.gf_...`,
    y compris les comparaisons. Les deux listes sont indépendantes : une même
    clé peut figurer à la fois dans `ecrit` et dans `lit` si elle est écrite
    puis relue. Renvoie `{"ecrit": [...], "lit": [...]}` avec des listes
    triées sans doublon.
    """
    propre = sans_commentaires(texte)
    ecrit: set[str] = set()
    lit: set[str] = set()

    for motif in (MOTIF_SET_STATE, MOTIF_SET_GLOBAL):
        for trouve in motif.finditer(propre):
            if trouve.group(2).startswith("gf_"):
                ecrit.add(trouve.group(2))
    for trouve in MOTIF_ECRITURE_DIRECTE.finditer(propre):
        ecrit.add(trouve.group(1))

    for trouve in MOTIF_LECTURE_STATE.finditer(propre):
        lit.add(trouve.group(1))

    return {"ecrit": sorted(ecrit), "lit": sorted(lit)}


def extraire_dependances(texte_manifeste: str) -> list[str]:
    """Dépendances dures d'un `fxmanifest.lua` : bloc `dependencies` et `dependency`.

    Seuls les noms `gf_*` et `oxmysql` sont gardés : les dépendances tierces
    comme `baseevents` sont écartées. Les commentaires sont retirés.
    Liste triée sans doublon.
    """
    propre = sans_commentaires(texte_manifeste)
    noms: list[str] = []
    for bloc in MOTIF_BLOC_DEPENDANCES.finditer(propre):
        for trouve in MOTIF_CHAINE_LITTERALE.finditer(bloc.group(1)):
            nom = trouve.group(2)
            if nom.startswith("gf_") or nom == "oxmysql":
                noms.append(nom)
    for trouve in MOTIF_DEPENDANCE_SEULE.finditer(propre):
        nom = trouve.group(2)
        if nom.startswith("gf_") or nom == "oxmysql":
            noms.append(nom)
    return _trier(noms)


def extraire_dependances_optionnelles(texte: str, ressource: str) -> list[str]:
    """Dépendances optionnelles via `GetResourceState('gf_x')`, hors soi-même.

    Seuls les appels à un littéral `gf_x` différent de la ressource courante
    sont comptés ; les appels dynamiques sont ignorés. Liste triée sans doublon.
    """
    propre = sans_commentaires(texte)
    return _trier(
        trouve.group(2)
        for trouve in MOTIF_GET_RESOURCE_STATE.finditer(propre)
        if trouve.group(2) != ressource and trouve.group(2).startswith("gf_")
    )


def lire_ressources(racine: Path) -> list[str]:
    """Noms des ressources `gf_*` démarrées dans `server-data/server.cfg`.

    Les lignes `ensure gf_...` sont lues avec leurs espaces éventuels,
    dédupliquées en conservant l'ordre d'apparition. Les autres ressources
    (`mapmanager`, `oxmysql`, ...) sont ignorées.
    """
    texte = (racine / "server-data" / "server.cfg").read_text(encoding="utf-8")
    vues: set[str] = set()
    ressources: list[str] = []
    for trouve in MOTIF_ENSURE.finditer(texte):
        nom = trouve.group(1)
        if nom not in vues:
            vues.add(nom)
            ressources.append(nom)
    return ressources


def _fichiers_lua(dossier: Path) -> list[Path]:
    """Fichiers `*.lua` d'un dossier, récursivement, triés (jamais de `.js`)."""
    return sorted(
        (fichier for fichier in dossier.rglob("*.lua") if fichier.is_file()),
        key=lambda fichier: fichier.relative_to(dossier).as_posix(),
    )


def extraire_contrat(racine: Path, ressource: str) -> dict:
    """Construit le contrat extrait du code d'une ressource démarrée.

    Lit récursivement tous les `.lua` du dossier `ressources/[gunfight]/<nom>/`
    et le `fxmanifest.lua`, puis renvoie les huit clés extraites. La clé
    `dette` est présente mais vide : la dette se calcule sur l'ensemble des
    contrats avec `dette_attendue`. Lève OSError si le dossier, un fichier Lua
    ou le manifeste est illisible.
    """
    dossier = racine / "server-data" / "resources" / "[gunfight]" / ressource
    manifeste = dossier / "fxmanifest.lua"
    if not dossier.is_dir():
        raise OSError(f"Dossier de ressource introuvable : {dossier}")
    if not manifeste.is_file():
        raise OSError(f"Manifeste introuvable : {manifeste}")

    textes = [
        fichier.read_text(encoding="utf-8", errors="replace")
        for fichier in _fichiers_lua(dossier)
    ]
    code = "\n".join(textes)
    manifeste_texte = manifeste.read_text(encoding="utf-8", errors="replace")

    return {
        "ressource": ressource,
        "exports": extraire_exports(code),
        "consomme": extraire_consommes(code, ressource),
        "emet": extraire_evenements_emis(code, ressource),
        "ecoute": extraire_evenements_ecoutes(code, ressource),
        "state_bags": extraire_state_bags(code),
        "dependances": {
            "dures": extraire_dependances(manifeste_texte),
            "optionnelles": extraire_dependances_optionnelles(code, ressource),
        },
        "dette": [],
    }


def _cible_consommee(consommation: str) -> str:
    """Nom de la ressource cible d'une entrée `gf_x:Nom`."""
    return consommation.split(":", 1)[0]


def dependances_cachees(contrat: dict) -> list[str]:
    """Entrées `dependance-cachee:gf_x` attendues pour un contrat.

    Une consommation d'export de `gf_x` est une dépendance cachée si `gf_x`
    n'est ni dans les dépendances dures ni dans les dépendances optionnelles.
    Liste triée sans doublon.
    """
    dependances = contrat["dependances"]
    connues = set(dependances["dures"]) | set(dependances["optionnelles"])
    cachees = {
        _cible_consommee(entree)
        for entree in contrat["consomme"]
        if _cible_consommee(entree) not in connues
    }
    return sorted(f"dependance-cachee:{nom}" for nom in cachees)


def cycles_deux(contrats: dict[str, dict]) -> list[tuple[str, str]]:
    """Cycles de longueur deux du graphe des contrats.

    Une arête `A -> B` existe si A consomme un export de B ou si A a B dans
    ses dépendances dures. Renvoie les paires non ordonnées `(a, b)` avec
    `a < b`, triées.
    """
    arêtes: dict[str, set[str]] = {}
    for ressource, contrat in contrats.items():
        cibles = {
            _cible_consommee(entree) for entree in contrat["consomme"]
        }
        cibles.update(contrat["dependances"]["dures"])
        arêtes[ressource] = {cible for cible in cibles if cible in contrats}

    cycles: set[tuple[str, str]] = set()
    for a, cibles in arêtes.items():
        for b in cibles:
            if a != b and a in arêtes.get(b, set()):
                cycles.add((a, b) if a < b else (b, a))
    return sorted(cycles)


def dette_attendue(contrats: dict[str, dict]) -> dict[str, list[str]]:
    """Dette attendue (dépendances cachées et cycles) pour chaque ressource.

    Renvoie un dictionnaire `{ressource: [entrees triees]}` couvrant toutes
    les ressources fournies. Aucune entrée n'est ajoutée pour une ressource
    absente de `contrats`.
    """
    cycles = cycles_deux(contrats)
    resultat: dict[str, list[str]] = {}
    for ressource, contrat in contrats.items():
        entrees = set(dependances_cachees(contrat))
        for a, b in cycles:
            if ressource == a:
                entrees.add(f"cycle:{b}")
            elif ressource == b:
                entrees.add(f"cycle:{a}")
        resultat[ressource] = sorted(entrees)
    return resultat


def _format_liste(titre: str, valeurs: list[str], lignes: list[str]) -> None:
    """Ajoute un titre et une puce par valeur, ou `Aucun.` si la liste est vide."""
    lignes.append(f"- {titre}")
    if valeurs:
        for valeur in valeurs:
            lignes.append(f"  - {valeur}")
    else:
        lignes.append("  - Aucun.")


def generer_doc(contrats: dict[str, dict]) -> str:
    """Génère le texte déterministe de `docs/contrats.md` à partir du registre.

    Le document contient une section par ressource triée, puis un tableau des
    propriétaires des événements `gf:*` (union des émetteurs et écouteurs).
    Aucune date ni valeur non déterministe n'est introduite : deux appels avec
    les mêmes contrats produisent exactement le même texte, newline final compris.
    """
    lignes = [
        "# Contrats entre ressources",
        "",
        "Ce document est généré par `python scripts/contrats.py --doc` : "
        "il ne se modifie pas à la main.",
        "",
    ]

    for ressource in sorted(contrats):
        contrat = contrats[ressource]
        etat = contrat["state_bags"]
        dependances = contrat["dependances"]
        lignes.append(f"## {ressource}")
        lignes.append("")
        _format_liste("Exports fournis", contrat["exports"], lignes)
        _format_liste("Exports consommés", contrat["consomme"], lignes)
        _format_liste("Événements émis", contrat["emet"], lignes)
        _format_liste("Événements écoutés", contrat["ecoute"], lignes)
        _format_liste("State bags écrits", etat["ecrit"], lignes)
        _format_liste("State bags lus", etat["lit"], lignes)
        _format_liste("Dépendances dures", dependances["dures"], lignes)
        _format_liste("Dépendances optionnelles", dependances["optionnelles"], lignes)
        _format_liste("Dette", contrat["dette"], lignes)
        lignes.append("")

    emetteurs: dict[str, set[str]] = {}
    ecouteurs: dict[str, set[str]] = {}
    for ressource, contrat in contrats.items():
        for evenement in contrat["emet"]:
            if evenement.startswith("gf:"):
                emetteurs.setdefault(evenement, set()).add(ressource)
        for evenement in contrat["ecoute"]:
            if evenement.startswith("gf:"):
                ecouteurs.setdefault(evenement, set()).add(ressource)

    evenements = sorted(set(emetteurs) | set(ecouteurs))
    lignes.append("## Propriétaires des événements `gf:*`")
    lignes.append("")
    lignes.append("| Événement | Émetteurs | Écouteurs |")
    lignes.append("| --- | --- | --- |")
    for evenement in evenements:
        emis = ", ".join(sorted(emetteurs.get(evenement, set()))) or "aucun"
        ecoutes = ", ".join(sorted(ecouteurs.get(evenement, set()))) or "aucun"
        lignes.append(f"| {evenement} | {emis} | {ecoutes} |")
    lignes.append("")
    return "\n".join(lignes)


def _est_liste_textes(valeur: object) -> bool:
    """Dit si une valeur JSON est une liste de textes."""
    return isinstance(valeur, list) and all(isinstance(element, str) for element in valeur)


def _lire_contrats(
    racine: Path, ressources: list[str]
) -> tuple[dict[str, dict], list[str]]:
    """Lit et valide les contrats ; renvoie (contrats valides, messages)."""
    contrats: dict[str, dict] = {}
    messages: list[str] = []
    for ressource in ressources:
        chemin = (
            racine
            / "server-data"
            / "resources"
            / "[gunfight]"
            / ressource
            / "contrat.json"
        )
        if not chemin.is_file():
            messages.append(f"{ressource} : contrat.json absent ({chemin}).")
            continue
        try:
            donnees = json.loads(chemin.read_text(encoding="utf-8"))
        except (OSError, ValueError) as erreur:
            messages.append(f"{ressource} : contrat.json illisible ({erreur}).")
            continue
        if not isinstance(donnees, dict):
            messages.append(f"{ressource} : contrat.json doit être un objet JSON.")
            continue
        manquantes = [cle for cle in CLES_CONTRAT if cle not in donnees]
        if manquantes:
            messages.append(
                f"{ressource} : contrat.json sans clé(s) {', '.join(manquantes)}."
            )
            continue
        if not isinstance(donnees["ressource"], str):
            messages.append(f"{ressource} : la clé 'ressource' doit être un texte.")
            continue
        if donnees["ressource"] != ressource:
            messages.append(
                f"{ressource} : contrat.json déclare la ressource "
                f"'{donnees['ressource']}'."
            )
            continue
        invalides = [
            cle for cle in CLES_LISTES if not _est_liste_textes(donnees[cle])
        ]
        if not isinstance(donnees["dette"], list) or not all(
            isinstance(element, str) for element in donnees["dette"]
        ):
            invalides.append("dette")
        etat = donnees["state_bags"]
        if not isinstance(etat, dict) or not all(
            _est_liste_textes(etat.get(cle)) for cle in ("ecrit", "lit")
        ):
            invalides.append("state_bags.ecrit/lit")
        dependances = donnees["dependances"]
        if not isinstance(dependances, dict) or not all(
            _est_liste_textes(dependances.get(cle)) for cle in ("dures", "optionnelles")
        ):
            invalides.append("dependances.dures/optionnelles")
        if invalides:
            messages.append(
                f"{ressource} : contrat.json invalide ({', '.join(invalides)})."
            )
            continue
        contrats[ressource] = donnees
    return contrats, messages


def _difference(reference: list[str], observe: list[str]) -> tuple[list[str], list[str]]:
    """Éléments en trop puis éléments manquants entre deux listes triées."""
    ref, obs = set(reference), set(observe)
    return sorted(obs - ref), sorted(ref - obs)


def _message_ecart(ressource: str, cle: str, extrait: list[str], declare: list[str]) -> str:
    """Message décrivant un écart entre extraction et contrat pour une clé."""
    en_trop, manquants = _difference(extrait, declare)
    parties: list[str] = []
    if en_trop:
        parties.append(f"en trop : {', '.join(en_trop)}")
    if manquants:
        parties.append(f"manquants : {', '.join(manquants)}")
    return f"{ressource} : {cle} : " + " ; ".join(parties) + "."


def _handlers_locaux(racine: Path, ressource: str) -> set[str]:
    """Noms des événements `gf_x:*` propres à une ressource, trouvés dans son code.

    Le contrat de `gf_x` exclut ses propres préfixes ; pour le contrôle des
    émissions entrantes on scanne donc directement ses fichiers Lua (sans
    commentaires) à la recherche de `AddEventHandler` / `RegisterNetEvent`.
    """
    dossier = racine / "server-data" / "resources" / "[gunfight]" / ressource
    if not dossier.is_dir():
        return set()
    code = "\n".join(
        fichier.read_text(encoding="utf-8", errors="replace")
        for fichier in _fichiers_lua(dossier)
    )
    return {
        trouve.group(2)
        for trouve in MOTIF_ECOUTEUR.finditer(sans_commentaires(code))
    }


def verifier(racine: Path | None = None) -> list[str]:
    """Vérifie le registre et renvoie tous les écarts en français.

    Les contrôles a à i sont appliqués dans cet ordre, sur les ressources triées.
    c, d et e restent fondés sur le code extrait (et non sur le seul registre)
    pour constituer une vérification réelle. La liste renvoyée est vide si tout
    est conforme ; la fonction ne lève pas d'exception sur un contrat absent ou
    invalide et n'écrit aucun fichier.
    """
    base = racine if racine is not None else RACINE
    ressources = lire_ressources(base)
    messages: list[str] = []

    # a. Contrats présents, lisibles et valides.
    contrats, messages = _lire_contrats(base, ressources)

    # Extractions du code : référence pour b, c, d, e et f.
    extraits: dict[str, dict] = {}
    for ressource in ressources:
        try:
            extraits[ressource] = extraire_contrat(base, ressource)
        except OSError as erreur:
            messages.append(f"{ressource} : extraction impossible ({erreur}).")

    for ressource in sorted(ressources):
        # b. Le registre doit égaler l'extraction du code.
        if ressource in contrats and ressource in extraits:
            extrait, contrat = extraits[ressource], contrats[ressource]
            for cle in CLES_LISTES:
                if contrat[cle] != extrait[cle]:
                    messages.append(
                        _message_ecart(ressource, cle, extrait[cle], contrat[cle])
                    )
            for sous_cle in ("ecrit", "lit"):
                if contrat["state_bags"][sous_cle] != extrait["state_bags"][sous_cle]:
                    messages.append(
                        _message_ecart(
                            ressource,
                            f"state_bags.{sous_cle}",
                            extrait["state_bags"][sous_cle],
                            contrat["state_bags"][sous_cle],
                        )
                    )
            for sous_cle in ("dures", "optionnelles"):
                if (
                    contrat["dependances"][sous_cle]
                    != extrait["dependances"][sous_cle]
                ):
                    messages.append(
                        _message_ecart(
                            ressource,
                            f"dependances.{sous_cle}",
                            extrait["dependances"][sous_cle],
                            contrat["dependances"][sous_cle],
                        )
                    )

        # c. Chaque export consommé doit exister chez le fournisseur.
        if ressource in extraits:
            for consommation in extraits[ressource]["consomme"]:
                cible = _cible_consommee(consommation)
                if cible not in ressources:
                    messages.append(
                        f"{ressource} : consomme {consommation} mais {cible} "
                        "n'est pas une ressource démarrée."
                    )
                    continue
                nom_export = consommation.split(":", 1)[1]
                if cible in extraits and nom_export not in extraits[cible]["exports"]:
                    messages.append(
                        f"{ressource} : l'export {consommation} n'existe pas "
                        f"parmi les exports fournis par {cible}."
                    )

        # d. Chaque événement émis vers une autre ressource doit y être écouté.
        if ressource in extraits:
            for evenement in extraits[ressource]["emet"]:
                if not evenement.startswith("gf:") and ":" in evenement:
                    cible = evenement.split(":", 1)[0]
                    if evenement not in _handlers_locaux(base, cible):
                        messages.append(
                            f"{ressource} : émet {evenement} mais {cible} "
                            "n'a aucun handler pour cet événement."
                        )

        # e. Chaque événement gf:* écouté doit avoir au moins un émetteur.
        if ressource in extraits:
            emetteurs = {
                evenement
                for extrait in extraits.values()
                for evenement in extrait["emet"]
            }
            for evenement in extraits[ressource]["ecoute"]:
                if evenement.startswith("gf:") and evenement not in emetteurs:
                    messages.append(
                        f"{ressource} : écoute {evenement} mais aucune ressource "
                        "ne l'émet."
                    )

    if contrats:
        dette = dette_attendue(contrats)
        cycles = cycles_deux(contrats)

        for ressource in sorted(contrats):
            contrat = contrats[ressource]
            declaree = contrat["dette"]
            attendue = dette[ressource]

            # f. Dépendances cachées déclarées ou non dans la dette.
            if ressource in extraits:
                connues = (
                    set(extraits[ressource]["dependances"]["dures"])
                    | set(extraits[ressource]["dependances"]["optionnelles"])
                )
                cachees = {
                    _cible_consommee(entree)
                    for entree in extraits[ressource]["consomme"]
                    if _cible_consommee(entree) not in connues
                }
                for cible in sorted(cachees):
                    entree = f"dependance-cachee:{cible}"
                    if entree not in declaree:
                        if cible not in ressources:
                            messages.append(
                                f"{ressource} : consomme un export de {cible} "
                                f"(ressource non démarrée) sans dette {entree}."
                            )
                        else:
                            messages.append(
                                f"{ressource} : dépendance cachée envers {cible} "
                                f"non déclarée dans la dette ({entree} manquante)."
                            )
            for entree in declaree:
                if entree.startswith("dependance-cachee:"):
                    cible = entree.split(":", 1)[1]
                    if f"dependance-cachee:{cible}" not in attendue:
                        messages.append(
                            f"{ressource} : dette {entree} périmée (plus aucune "
                            "dépendance cachée correspondante)."
                        )

            # g. Cycles de longueur deux : la dette doit être notée des deux côtés.
            for a, b in cycles:
                for porteur, cible in ((a, b), (b, a)):
                    if porteur == ressource:
                        entree = f"cycle:{cible}"
                        if entree not in declaree:
                            messages.append(
                                f"{ressource} : cycle de longueur deux avec "
                                f"{cible} non noté dans la dette ({entree} manquante)."
                            )
            for entree in declaree:
                if entree.startswith("cycle:"):
                    cible = entree.split(":", 1)[1]
                    if f"cycle:{cible}" not in attendue:
                        messages.append(
                            f"{ressource} : dette {entree} périmée (plus aucun "
                            "cycle de longueur deux correspondant)."
                        )

            # h. Doublons et entrées inconnues dans la dette.
            vues: set[str] = set()
            for entree in declaree:
                if entree in vues:
                    messages.append(f"{ressource} : dette en double : {entree}.")
                vues.add(entree)
                if not (
                    entree.startswith("dependance-cachee:") or entree.startswith("cycle:")
                ):
                    messages.append(
                        f"{ressource} : dette inconnue : {entree}."
                    )

    # i. La documentation doit être identique au générateur, octet pour octet.
    if contrats:
        doc_generee = generer_doc(contrats)
        if (base / "docs" / "contrats.md").is_file():
            try:
                doc_actuelle = (base / "docs" / "contrats.md").read_bytes()
            except OSError as erreur:
                messages.append(f"docs/contrats.md illisible ({erreur}).")
            else:
                if doc_actuelle != doc_generee.encode("utf-8"):
                    messages.append(
                        "docs/contrats.md n'est pas à jour : régénère-le avec "
                        "`python scripts/contrats.py --doc`."
                    )
        else:
            messages.append(
                "docs/contrats.md absent : génère-le avec "
                "`python scripts/contrats.py --doc`."
            )

    return messages


def _ecrire(chemin: Path, contenu: str) -> bool:
    """Écrit un texte UTF-8 ; renvoie False si l'écriture est impossible."""
    try:
        chemin.parent.mkdir(parents=True, exist_ok=True)
        chemin.write_text(contenu, encoding="utf-8", newline="\n")
    except OSError:
        return False
    return True


def _initialiser(racine: Path) -> int:
    """Extrait les contrats et écrit un `contrat.json` par ressource démarrée."""
    ressources = lire_ressources(racine)
    contrats: dict[str, dict] = {}
    for ressource in ressources:
        dossier = racine / "server-data" / "resources" / "[gunfight]" / ressource
        manifeste = dossier / "fxmanifest.lua"
        if not dossier.is_dir():
            print(f"ERREUR : dossier de ressource introuvable : {dossier}", file=sys.stderr)
            return 2
        if not manifeste.is_file():
            print(f"ERREUR : manifeste introuvable : {manifeste}", file=sys.stderr)
            return 2
        try:
            contrats[ressource] = extraire_contrat(racine, ressource)
        except OSError as erreur:
            print(f"ERREUR : extraction impossible : {erreur}", file=sys.stderr)
            return 2

    dette = dette_attendue(contrats)
    echecs = 0
    for ressource in sorted(contrats):
        contrat = dict(contrats[ressource])
        contrat["dette"] = dette[ressource]
        chemin = (
            racine
            / "server-data"
            / "resources"
            / "[gunfight]"
            / ressource
            / "contrat.json"
        )
        contenu = json.dumps(contrat, ensure_ascii=False, indent=2) + "\n"
        if _ecrire(chemin, contenu):
            print(f"Contrat écrit : {chemin}")
        else:
            echecs += 1
            print(f"ERREUR : écriture impossible : {chemin}", file=sys.stderr)

    if echecs:
        print(f"{echecs} contrat(s) non écrit(s).", file=sys.stderr)
        return 1
    print(f"{len(contrats)} contrat(s) écrit(s) avec succès.")
    return 0


def _generer_documentation(racine: Path) -> int:
    """Lit les contrats et génère `docs/contrats.md` ; ne l'écrit pas à la main."""
    ressources = lire_ressources(racine)
    contrats, messages = _lire_contrats(racine, ressources)
    if messages:
        for message in messages:
            print(message, file=sys.stderr)
        return 2
    chemin_doc = racine / "docs" / "contrats.md"
    if not _ecrire(chemin_doc, generer_doc(contrats)):
        print(f"ERREUR : écriture impossible : {chemin_doc}", file=sys.stderr)
        return 1
    print(f"Documentation générée : {chemin_doc}")
    return 0


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée CLI : modes mutuellement exclusifs, --verifier par défaut."""
    analyseur = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog="Le mode --verifier est le défaut et ne modifie aucun fichier.",
    )
    groupe = analyseur.add_mutually_exclusive_group()
    groupe.add_argument(
        "--initialiser",
        action="store_true",
        help="extrait le code et écrit un contrat.json par ressource démarrée",
    )
    groupe.add_argument(
        "--doc",
        action="store_true",
        help="génère docs/contrats.md depuis les contrat.json",
    )
    groupe.add_argument(
        "--verifier",
        action="store_true",
        help="vérifie le registre et la documentation (mode par défaut)",
    )
    args = analyseur.parse_args(argv)

    if args.initialiser:
        return _initialiser(RACINE)
    if args.doc:
        return _generer_documentation(RACINE)

    messages = verifier()
    if messages:
        for message in messages:
            print(message)
        return 1
    print("Contrats conformes : code, registre et documentation concordent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
