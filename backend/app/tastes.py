"""Smaak per persoon: wat iemand niet lust of heel lekker vindt, op ingrediëntniveau.

- Handmatig: "Hannah lust geen paprika", "Suze is dol op kip" (`member_preferences`).
- Afgeleid (D4): komt een ingrediënt vaak voor in recepten die iemand 👎 gaf en nooit in recepten die die persoon 👍
  gaf, dan stelt Miso voor het als afkeer te noteren. Het gezin bevestigt of wuift het weg; Miso zet nooit zelf iets.
Het weekvoorstel gebruikt dit: een recept met iets dat iemand niet lust gaat omlaag en krijgt een waarschuwing.
"""

import json
import re

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.clients.mealie import clean_search
from app.models import MemberPreference, Rating, Recipe
from app.planning import get_setting, set_setting

KINDS = ("dislike", "like")
MIN_DOWN = 2  # minstens zoveel recepten met 👎 voordat Miso iets voorstelt
DISMISSED_KEY = "taste_dismissed"  # ["hannah:paprika", ...]: "nee, dat klopt niet"
STOP = {"zout", "peper", "water", "olie", "boter", "suiker", "bloem", "stuks", "gram", "deciliter", "eetlepel",
        "theelepel", "snufje", "beetje", "verse", "gedroogde", "grote", "kleine"}


def clean_term(term: str) -> str:
    return " ".join(str(term).lower().split())[:100]


def term_in_text(term: str, text: str) -> bool:
    """Korte termen ("ui") alleen aan het begin van een woord (niet in "kruiden"); langere overal ("puntpaprika")."""
    if not term:
        return False
    low = text.lower()
    if len(term) >= 5:
        return term in low
    return re.search(r"\b" + re.escape(term), low) is not None


def recipe_text(recipe: Recipe) -> str:
    return " | ".join(str(i.get("text", "")) for i in recipe.ingredients if not i.get("skip") or i.get("auto_skip"))


def preferences(db: Session) -> dict[str, list[MemberPreference]]:
    out: dict[str, list[MemberPreference]] = {}
    for p in db.execute(select(MemberPreference).order_by(MemberPreference.kind, MemberPreference.term)).scalars():
        out.setdefault(p.member_id, []).append(p)
    return out


def taste_hits(db: Session, recipes: list[Recipe], members_list: list[dict]) -> dict[int, dict]:
    """Per recept: {"dislikes": [(naam, term)], "likes": [(naam, term)]} voor de gezinsleden die voorkeuren hebben."""
    names = {m["id"]: m["name"] for m in members_list}
    prefs = [(names[mid], p) for mid, rows in preferences(db).items() if mid in names for p in rows]
    if not prefs:
        return {}
    out: dict[int, dict] = {}
    for r in recipes:
        text = recipe_text(r)
        hit = {"dislikes": [], "likes": []}
        for name, p in prefs:
            if term_in_text(p.term, text):
                hit["dislikes" if p.kind == "dislike" else "likes"].append((name, p.term))
        if hit["dislikes"] or hit["likes"]:
            out[r.id] = hit
    return out


def head_term(ing: dict) -> str:
    """Het belangrijkste woord van een ingrediënt ("2 rode puntpaprika's" -> "puntpaprika's"); leeg als er geen is."""
    q = clean_search(ing.get("search") or ing.get("text", "")).lower()
    words = [w for w in re.findall(r"[a-zà-ÿ]+", q) if len(w) >= 3 and w not in STOP]
    return words[-1] if words else ""


def _stem(term: str) -> str:
    """Eenvoudige enkelvoud: "paprika's" -> "paprika", "uien" -> "ui"; genoeg om recepten te groeperen."""
    t = re.sub(r"'s$", "", term)
    if t.endswith("en") and len(t) > 5:
        t = t[:-2]
    return t


def load_dismissed(db: Session) -> set[str]:
    try:
        data = json.loads(get_setting(db, DISMISSED_KEY) or "[]")
    except ValueError:
        return set()
    return {str(x) for x in data} if isinstance(data, list) else set()


def dismiss(db: Session, member_id: str, term: str) -> None:
    data = load_dismissed(db) | {f"{member_id}:{clean_term(term)}"}
    set_setting(db, DISMISSED_KEY, json.dumps(sorted(data)))


def suggest_dislikes(db: Session, members_list: list[dict]) -> list[dict]:
    """Voorgestelde afkeer uit 👎: [{"member_id", "name", "term", "down", "up"}]. Per persoon: een recept telt als 👎
    als die persoon er netto meer 👎 dan 👍 voor gaf. Voorgesteld wordt een ingrediënt dat in minstens `MIN_DOWN`
    👎-recepten zit en in minder dan de helft zoveel 👍-recepten."""
    names = {m["id"]: m["name"] for m in members_list}
    votes: dict[str, dict[int, int]] = {}
    for r in db.execute(select(Rating).where(Rating.member_id != "")).scalars():
        if r.member_id in names and r.rating in ("up", "down"):
            votes.setdefault(r.member_id, {}).setdefault(r.recipe_id, 0)
            votes[r.member_id][r.recipe_id] += 1 if r.rating == "up" else -1
    if not votes:
        return []
    recipes = {r.id: r for r in db.execute(select(Recipe)).scalars()}
    have = {(mid, p.term) for mid, rows in preferences(db).items() for p in rows}
    dismissed = load_dismissed(db)
    out: list[dict] = []
    for mid, per_recipe in votes.items():
        down: dict[str, int] = {}
        up: dict[str, int] = {}
        for rid, net in per_recipe.items():
            recipe = recipes.get(rid)
            if not recipe or net == 0:
                continue
            terms = {_stem(t) for t in (head_term(i) for i in recipe.ingredients if not i.get("skip") and not i.get("auto_skip")) if t}
            bucket = down if net < 0 else up
            for t in terms:
                bucket[t] = bucket.get(t, 0) + 1
        for term, n in down.items():
            if n < MIN_DOWN or up.get(term, 0) * 2 >= n:
                continue
            if (mid, term) in have or f"{mid}:{term}" in dismissed:
                continue
            out.append({"member_id": mid, "name": names[mid], "term": term, "down": n, "up": up.get(term, 0)})
    out.sort(key=lambda x: (-x["down"], x["name"], x["term"]))
    return out
