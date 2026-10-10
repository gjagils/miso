"""AH-maaltijdpakketten (verspakketten) als recepten: bulk ophalen en maandelijks bijwerken.

1. Alle Allerhande-recepten met "verspakket" in de titel ophalen (GraphQL recipeSearch, per 100).
2. Huidig assortiment: verspakket-producten die nu leverbaar zijn.
3. Per recept: de pakketregel ("770 g AH gesneden verspakketten ...") koppelen aan een leverbaar pakket.
   Gelukt -> recept toevoegen/bijwerken met label "maaltijdpakket" en het pakket als product.
   Niet (meer) leverbaar -> een eerder toegevoegd pakketrecept wordt opgeruimd (archived), niet verwijderd.
AH wisselt de samenstelling: bijwerken vervangt ingrediënten/bereiding, handmatige productkeuzes blijven staan.
"""

import re
import unicodedata
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.clients.ah import ah_client, convert_ah_recipe
from app.logging_config import logger
from app.matching import MATCH_VERSION, _stem
from app.models import Recipe

COLLECTION = "maaltijdpakket"
SEARCH_GQL = """query RecipeSearch($query: RecipeSearchParams!) {
  recipeSearch(query: $query) { page { total } result { id title } }
}"""
PRODUCT_QUERIES = ("verspakket", "gesneden verspakket", "vega verspakket", "ah verspakket", "biologisch verspakket")
STATUS: dict = {"running": False, "done": 0, "total": 0, "new": 0, "updated": 0, "archived": 0, "merged": 0, "error": None,
                "finished": None}


async def pack_recipes() -> list[dict]:
    out, start = [], 0
    while True:
        data = await ah_client.graphql(SEARCH_GQL, {"query": {"searchText": "verspakket", "size": 100, "start": start}},
                                       anonymous=True)
        res = data["recipeSearch"]["result"]
        out += [r for r in res if "verspakket" in r["title"].lower()]
        total = (data["recipeSearch"].get("page") or {}).get("total") or 0
        start += 100
        if not res or start >= total or start >= 1000:
            return list({r["id"]: r for r in out}.values())


async def current_packs() -> list[dict]:
    seen: dict[int, dict] = {}
    for q in PRODUCT_QUERIES:
        for p in await ah_client._search_legacy(q, 100):
            if "verspakket" in p["name"].lower() and p.get("available"):
                seen[p["id"]] = p
    return list(seen.values())


def pack_line(ingredients: list[dict]) -> int | None:
    for i, ing in enumerate(ingredients):
        if "verspakket" in ing.get("text", "").lower():
            return i
    return None


GENERIC = {"ah", "gesneden", "verspakket", "verspakketten", "vega", "biologisch", "met", "en", "van", "de", "het",
           "stijl", "pers", "persoons", "min", "mex", "culis", "keuze", "seizoensfavoriet", "g", "kg", "groente"}


def _key_words(text: str) -> set[str]:
    words = re.findall(r"[a-zà-ÿ]+", unicodedata.normalize("NFKD", text.lower()).encode("ascii", "ignore").decode())
    return {_stem(w) for w in words if w not in GENERIC and len(w) > 1}


def best_pack(text: str, packs: list[dict], title: str = "") -> dict | None:
    """Streng: alle kenmerkende woorden van het pakket staan in de receptregel, en die regel gaat grotendeels
    over dat pakket ("paprikasoep" is geen "gehaktschotel", "kip Hawaï" geen "kip siam")."""
    line, name = _key_words(text), _key_words(title)
    best, best_cover = None, 0.0
    for p in packs:
        prod = _key_words(p["name"])
        if not prod or not prod <= line:
            continue
        cover = len(prod) / len(line) + (1.0 if name and prod <= name else 0.0)  # titel beslist bij twijfel
        if cover >= 0.5 and cover > best_cover:
            best, best_cover = p, cover
    return best


def name_key(name: str) -> str:
    """'AH verspakket \'Japanse\' teriyaki' en 'AH verspakket Japanse teriyaki' -> zelfde sleutel."""
    from app.wishes import display_name

    return re.sub(r"[^a-z0-9]+", " ", display_name(name).lower()).strip()


def dedupe(db: Session) -> int:
    """Dubbele pakketrecepten (zelfde naam) samenvoegen: bewaar het recept met geschiedenis, verwijder lege kopieën."""
    from app.api.routes import remove_recipe
    from app.usage import plan_stats

    stats = plan_stats(db)
    groups: dict[str, list[Recipe]] = {}
    for r in db.execute(select(Recipe)).scalars():
        if "verspakket" in r.name.lower():
            groups.setdefault(name_key(r.name), []).append(r)
    removed = 0
    for rs in groups.values():
        if len(rs) < 2:
            continue
        # houden: gepland/gekookt/favoriet, dan het oudste (eigen import)
        rs.sort(key=lambda r: (-(stats.get(r.id, {}).get("planned", 0) + (r.cooked_count or 0) + 10 * bool(r.favorite)), r.id))
        keep = rs[0]
        keep.collection = COLLECTION
        for extra in rs[1:]:
            if stats.get(extra.id, {}).get("planned", 0) or extra.cooked_count or extra.favorite:
                continue  # zelf gebruikt: niet stilletjes weggooien
            if not keep.ah_recipe_id and extra.ah_recipe_id:
                keep.ah_recipe_id = extra.ah_recipe_id
            remove_recipe(db, extra)
            removed += 1
    db.commit()
    return removed


def _merge_ingredients(old: list[dict], new: list[dict]) -> list[dict]:
    """Nieuwe samenstelling van AH; handmatige keuzes bij dezelfde regeltekst blijven staan."""
    manual = {i.get("text"): i for i in old if i.get("manual")}
    return [manual.get(n.get("text"), n) for n in new]


async def sync(db: Session) -> dict:
    STATUS.update(running=True, done=0, total=0, new=0, updated=0, archived=0, merged=0, error=None, finished=None)
    try:
        recipes = await pack_recipes()
        packs = await current_packs()
        STATUS["total"] = len(recipes)
        all_recipes = db.execute(select(Recipe)).scalars().all()
        existing = {r.ah_recipe_id: r for r in all_recipes if r.ah_recipe_id}
        by_name = {name_key(r.name): r for r in all_recipes if "verspakket" in r.name.lower()}
        seen_names: set[str] = set()
        for item in recipes:
            try:
                data = convert_ah_recipe(await ah_client.get_recipe(item["id"]))
            except Exception as e:  # noqa: BLE001
                logger.warning("Verspakket-recept %s ophalen mislukt: %s", item["id"], e)
                STATUS["done"] += 1
                continue
            idx = pack_line(data["ingredients"])
            pack = best_pack(data["ingredients"][idx]["text"], packs, data["name"]) if idx is not None else None
            recipe = existing.get(item["id"]) or by_name.get(name_key(data["name"]))
            if name_key(data["name"]) in seen_names:  # AH heeft hetzelfde recept soms twee keer
                STATUS["done"] += 1
                continue
            seen_names.add(name_key(data["name"]))
            if not pack:  # niet (meer) leverbaar
                if recipe and recipe.collection == COLLECTION and not recipe.archived:
                    recipe.archived = True
                    STATUS["archived"] += 1
                STATUS["done"] += 1
                continue
            ings = data["ingredients"]
            ings[idx] = {**ings[idx], "product": {k: v for k, v in pack.items() if k != "unit_price"},
                         "quantity": 1, "match_v": MATCH_VERSION, "source": "maaltijdpakket"}
            if recipe is None:
                recipe = Recipe(name=data["name"], description=data["description"], servings=data["servings"],
                                total_time=data["total_time"], ah_recipe_id=item["id"],
                                source_url=f"https://www.ah.nl/allerhande/recept/R-R{item['id']}",
                                image_url=data.get("image_url", ""), collection=COLLECTION)
                recipe.ingredients = ings
                recipe.instructions = data["instructions"]
                db.add(recipe)
                by_name[name_key(data["name"])] = recipe
                STATUS["new"] += 1
            else:
                recipe.ingredients = _merge_ingredients(recipe.ingredients, ings)
                recipe.instructions = data["instructions"]
                recipe.total_time = data["total_time"] or recipe.total_time
                recipe.collection = COLLECTION  # zelf opgeruimd blijft opgeruimd
                STATUS["updated"] += 1
            db.commit()
            STATUS["done"] += 1
        STATUS["merged"] = dedupe(db)
        from app.api.routes import _set_setting

        _set_setting(db, "packs_synced_on", str(date.today()))
    except Exception as e:  # noqa: BLE001
        STATUS["error"] = str(e)
        logger.error("Maaltijdpakketten bijwerken mislukt: %s", e)
    finally:
        STATUS.update(running=False, finished=str(date.today()))
    logger.info("Maaltijdpakketten: %s nieuw, %s bijgewerkt, %s opgeruimd", STATUS["new"], STATUS["updated"],
                STATUS["archived"])
    return dict(STATUS)
