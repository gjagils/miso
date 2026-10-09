"""JSON endpoints used by the native iOS app."""
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api import routes
from app.clients.ah import ah_client
from app.config import settings
from app.database import get_db
from app.logging_config import logger
from app.models import Recipe

router = APIRouter(prefix="/api")


def _summary(r: Recipe) -> dict:
    return {
        "id": r.id, "name": r.name, "servings": r.servings, "total_time": r.total_time,
        "image_url": r.image_url, "gf_mode": r.gf_mode,
    }


class LoginPayload(BaseModel):
    pin: str = ""


@router.post("/login")
async def api_login(payload: LoginPayload):
    import hmac

    from app.main import session_token

    if not settings.app_pin:
        return {"ok": True, "token": ""}
    if hmac.compare_digest(payload.pin.strip(), settings.app_pin):
        return {"ok": True, "token": session_token()}
    import asyncio

    await asyncio.sleep(1)  # raden vertragen, net als de webpagina
    return JSONResponse({"ok": False, "error": "Pincode klopt niet."}, status_code=401)


@router.get("/recipes")
async def api_recipes(q: str = "", db: Session = Depends(get_db)):
    query = select(Recipe).order_by(Recipe.name)
    if q.strip():
        query = query.where(Recipe.name.ilike(f"%{q.strip()}%"))
    return {"recipes": [_summary(r) for r in db.execute(query).scalars()]}


@router.get("/recipes/{recipe_id}")
async def api_recipe(recipe_id: int, db: Session = Depends(get_db)):
    r = db.get(Recipe, recipe_id)
    if not r:
        raise HTTPException(404, "Recept niet gevonden")
    await routes.ensure_matched(db, r)
    return {
        **_summary(r),
        "description": r.description,
        "source_url": r.source_url,
        "gf_note": r.gf_note,
        "instructions": r.instructions,
        "ingredients": [_ing_json(i, idx) for idx, i in enumerate(r.ingredients)],
    }


def _ing_json(i: dict, idx: int) -> dict:
    return {
        "index": idx, "text": i["text"], "skip": bool(i.get("skip")), "gluten": bool(i.get("gluten")),
        "gf_search": i.get("gf_search", ""),
        "product": (i.get("product") or {}).get("name"),
        "product_id": (i.get("product") or {}).get("id"),
        "product_image": (i.get("product") or {}).get("image_url", ""),
        "quantity": i.get("quantity", 1), "pantry": bool(i.get("auto_skip")),
        "unit_size": (i.get("product") or {}).get("unit_size"),
        "manual": bool(i.get("manual")),
        "gf_product": (i.get("gf_product") or {}).get("name"),
        "gf_product_id": (i.get("gf_product") or {}).get("id"),
    }


class IngredientUpdate(BaseModel):
    text: str  # huidige tekst van de regel, ter controle
    product: dict | None = None  # AH-product (zoals /api/ah/search het geeft); None + skip=false = ontkoppelen
    skip: bool = False  # uitvinken: niet kopen
    quantity: int | None = None


@router.post("/recipes/{recipe_id}/ingredients/{index}")
async def api_update_ingredient(recipe_id: int, index: int, payload: IngredientUpdate, db: Session = Depends(get_db)):
    """Eén ingrediënt koppelen, uitvinken of aantal wijzigen (iOS). Een gekozen product is handmatig
    (wordt nooit automatisch overschreven) en wordt onthouden voor andere recepten."""
    from app.matching import MATCH_VERSION, needed, pack_size, packs_for

    r = db.get(Recipe, recipe_id)
    if not r:
        raise HTTPException(404, "Recept niet gevonden")
    ings = r.ingredients
    if not (0 <= index < len(ings)) or ings[index].get("text", "").strip() != payload.text.strip():
        return JSONResponse({"ok": False, "error": "Het recept is intussen gewijzigd. Ververs en probeer opnieuw."},
                            status_code=409)
    ing = ings[index]
    if payload.skip:
        ing.update(skip=True, auto_skip=False)
    elif payload.product and payload.product.get("id"):
        old = (ing.get("product") or {}).get("id")
        ing.update(product=payload.product, skip=False, auto_skip=False, manual=True, source="handmatig",
                   match_v=MATCH_VERSION)
        if old != payload.product["id"]:
            routes.learn_pref(db, ing)
            packs = packs_for(needed(ing.get("text", "")), pack_size(payload.product.get("unit_size", "")))
            ing["quantity"] = packs or 1
    else:
        ing.update(skip=False, auto_skip=False)
        if payload.product is None and "product" in payload.model_fields_set:
            ing.update(product=None, manual=False)
    if payload.quantity is not None:
        ing["quantity"] = max(1, min(99, payload.quantity))
    r.ingredients = ings
    db.commit()
    return {"ok": True, "ingredient": _ing_json(ing, index)}


class RecipeEdit(BaseModel):
    name: str | None = None
    servings: str | None = None
    total_time: str | None = None
    description: str | None = None
    instructions: list[str] | None = None
    ingredients: list[str] | None = None  # alle ingrediëntregels als tekst; ongewijzigde regels houden hun koppeling


@router.patch("/recipes/{recipe_id}")
async def api_edit_recipe(recipe_id: int, payload: RecipeEdit, db: Session = Depends(get_db)):
    r = db.get(Recipe, recipe_id)
    if not r:
        raise HTTPException(404, "Recept niet gevonden")
    for field in ("name", "servings", "total_time", "description"):
        value = getattr(payload, field)
        if value is not None:
            if field == "name" and not value.strip():
                return JSONResponse({"ok": False, "error": "Geef het recept een naam."}, status_code=400)
            setattr(r, field, value.strip())
    if payload.instructions is not None:
        r.instructions = [s.strip() for s in payload.instructions if s.strip()]
    if payload.ingredients is not None:
        old = {}
        for ing in r.ingredients:
            old.setdefault(ing.get("text", "").strip(), ing)
        new = []
        for text in (t.strip() for t in payload.ingredients):
            if text:
                new.append(old.pop(text, None) or {"text": text, "search": text, "skip": False, "quantity": 1,
                                                   "product": None})
        r.ingredients = new
    db.commit()
    return await api_recipe(recipe_id, db)  # koppelt nieuwe regels meteen (ensure_matched)


@router.delete("/recipes/{recipe_id}")
async def api_delete_recipe(recipe_id: int, db: Session = Depends(get_db)):
    r = db.get(Recipe, recipe_id)
    if not r:
        raise HTTPException(404, "Recept niet gevonden")
    routes.remove_recipe(db, r)
    return {"ok": True}


@router.get("/missing")
async def api_missing(db: Session = Depends(get_db)):
    """Ontbrekende AH-producten gegroepeerd (zoals de webpagina Ontbrekend); kiezen via POST /api/missing/assign."""
    from app.api.shopping import coverage, missing_groups

    return {"groups": missing_groups(db), "totaal": coverage(db)["totaal"]}


@router.get("/week")
async def api_week(week: str | None = None, db: Session = Depends(get_db)):
    """Week voor de apps. `recipes` (per dag) is het oude veld: alleen gekookte recepten, zodat de oude
    iOS-app (die met POST /api/plan de recepten terugstuurt) geen restjes/voorraad omzet. `entries` is
    de volledige lijst planregels (zie docs/plan-api.md)."""
    from app import planning
    from app.api.plan import entries_json

    monday = routes.parse_week(week)
    entries = planning.week_entries(db, monday)
    recipes = planning.recipes_for(db, entries)
    full = entries_json(db, entries)
    days = []
    for i in range(7):
        d = monday + timedelta(days=i)
        days.append({
            "date": str(d), "label": routes.day_label(d), "today": d == date.today(),
            "recipes": [{**_summary(recipes[e.recipe_id]), "entry_id": e.id}
                        for e in entries if e.date == str(d) and e.kind == "recipe" and e.recipe_id in recipes],
            "entries": [x for x in full if x["date"] == str(d)],
        })
    return {
        "week": str(monday), "prev_week": str(monday - timedelta(days=7)),
        "next_week": str(monday + timedelta(days=7)),
        "household_size": planning.household_size(db),
        "days": days, "status": routes.week_status(db, monday),
    }


@router.get("/allerhande/search")
async def api_allerhande_search(q: str = Query(..., min_length=1), db: Session = Depends(get_db)):
    try:
        results = await ah_client.search_recipes(q.strip())
    except Exception as e:
        logger.error("Allerhande search failed: %s", e)
        return JSONResponse({"ok": False, "error": f"Zoeken bij AH mislukt: {e}"}, status_code=502)
    saved = set(db.execute(select(Recipe.ah_recipe_id).where(Recipe.ah_recipe_id.is_not(None))).scalars())
    return {"ok": True, "results": [{**r, "saved": r["id"] in saved} for r in results]}
