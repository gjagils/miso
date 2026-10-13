"""Koken met wat er is (F11): welke eigen recepten kun je (grotendeels) maken van wat in de vriezer ligt en wat
je net gekocht hebt? Puur lokale gegevens: de vriezerlijst en de laatste boodschappenrondes uit `ah_trips`.

Restjes zijn al een planregel ("Rest van ...") en hoeven hier niet nog eens te worden gezocht.
Bestelt of zoekt niets bij AH.
"""

import re
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import ah_sync, planning, replenish
from app.models import FreezerItem, Recipe
from app.tastes import STOP, _stem, head_term

RECENT_DAYS = 4  # zo recent gekochte producten gelden als "nog in huis"
MIN_COVERED = 2  # zoveel ingrediënten moeten gedekt zijn voordat een recept wordt voorgesteld
MAX_SUGGESTIONS = 6
PLANNED_DAYS = 7  # recepten die de komende week al op het menu staan, laten we weg
NOISE = STOP | {"biologisch", "biologische", "huismerk", "vers", "verse", "pak", "zak", "bak", "fles", "kilo", "stuk",
                "wasbare", "rijp", "gesneden", "gewassen", "mix", "extra", "voordeel", "voordeelverpakking"}


def terms_of(name: str) -> set[str]:
    """Betekenisvolle woorden uit een productnaam of vriezeritem ("AH Biologisch Courgette" -> {"courgette"})."""
    out = set()
    for w in re.findall(r"[a-zà-ÿ]+", (name or "").lower()):
        if len(w) >= 4 and w not in NOISE:
            out.add(_stem(w))
    return out


def _match(inv: str, word: str) -> bool:
    if inv == word:
        return True
    short, long_ = (inv, word) if len(inv) <= len(word) else (word, inv)
    return len(short) >= 5 and short in long_


def inventory(db: Session, today: date | None = None) -> dict:
    """{"freezer": [{"name", "terms"}], "bought": [{"name", "date", "terms"}]} (zonder basisvoorraad)."""
    today = today or date.today()
    recipes = list(db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars())
    pantry = replenish.pantry_terms(recipes)
    freezer = [{"name": f.name, "terms": sorted(terms_of(f.name))}
               for f in db.execute(select(FreezerItem).where(FreezerItem.portions > 0)).scalars()]
    bought: dict[str, dict] = {}
    for trip in ah_sync.trips_since(db, today - timedelta(days=RECENT_DAYS)):
        for ln in trip.lines:
            name = str(ln.get("name") or "").strip()
            if not name or replenish.is_pantry(name, pantry):
                continue
            terms = terms_of(name)
            if terms and name.lower() not in bought:
                bought[name.lower()] = {"name": name, "date": trip.date, "terms": sorted(terms)}
    return {"freezer": [f for f in freezer if f["terms"]], "bought": list(bought.values())}


def suggest(db: Session, today: date | None = None) -> dict:
    today = today or date.today()
    inv = inventory(db, today)
    sources = [("vriezer", it) for it in inv["freezer"]] + [("gekocht", it) for it in inv["bought"]]
    planned = {e.recipe_id for e in planning.entries_between(db, today, today + timedelta(days=PLANNED_DAYS - 1))
               if e.recipe_id}
    from_freezer = {f.from_recipe_id for f in db.execute(select(FreezerItem)).scalars() if f.from_recipe_id}
    out = []
    if sources:
        recipes = db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars().all()
        for r in recipes:
            if r.id in planned or r.id in from_freezer:
                continue
            ings = [i for i in r.ingredients if not i.get("skip") and not i.get("auto_skip")]
            matches = []
            for ing in ings:
                word = _stem(head_term(ing))
                if not word:
                    continue
                for kind, item in sources:
                    if any(_match(t, word) for t in item["terms"]):
                        matches.append({"ingredient": str(ing.get("text", "")), "from": item["name"], "source": kind})
                        break
            if len(matches) >= MIN_COVERED:
                out.append({"recipe_id": r.id, "name": r.name, "image_url": r.image_url, "total_time": r.total_time,
                            "servings": r.servings, "covered": len(matches), "total": len(ings),
                            "missing_count": max(0, len(ings) - len(matches)), "matches": matches})
    out.sort(key=lambda s: (-s["covered"], s["missing_count"], s["name"]))
    return {"suggestions": out[:MAX_SUGGESTIONS],
            "inventory": {"freezer": [f["name"] for f in inv["freezer"]],
                          "bought": [{"name": b["name"], "date": b["date"]} for b in inv["bought"]]}}
