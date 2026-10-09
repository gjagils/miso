import asyncio
import json
import math
import re
import hmac
import io
import os
import time
from datetime import date, timedelta
from urllib.parse import parse_qs, urlparse

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from PIL import Image, ImageOps
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.clients.ah import ah_client, convert_ah_recipe
from app.clients.extractor import extract_recipe, fetch_url, suggest_gluten_free
from app.clients.mealie import MealieClient, clean_search, convert_recipe
from app.matching import MATCH_VERSION, choose, container_count, has_no_product, is_equipment, is_pantry, needed, pack_size, packs_for, query_terms, score, search_queries
from app.config import settings
from app.database import get_db
from app.logging_config import logger
from app.models import AppSetting, CartPush, PlanEntry, ProductPreference, Recipe
from app import planning

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")

IMAGE_DIR = os.path.join("data", "images")
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
DAYS = ["Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag", "Zondag"]
MONTHS = ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def parse_week(week: str | None) -> date:
    """ISO-datum -> maandag van die week. "next" = volgende week; leeg/ongeldig = deze week."""
    if week in ("next", "volgende"):
        return monday_of(date.today()) + timedelta(days=7)
    try:
        return monday_of(date.fromisoformat(week)) if week else monday_of(date.today())
    except ValueError:
        return monday_of(date.today())


def day_label(d: date) -> str:
    return f"{DAYS[d.weekday()]} {d.day} {MONTHS[d.month - 1]}"


def _get_setting(db: Session, key: str) -> str:
    row = db.execute(select(AppSetting).where(AppSetting.key == key)).scalar_one_or_none()
    return row.value if row else ""


def _set_setting(db: Session, key: str, value: str) -> None:
    row = db.execute(select(AppSetting).where(AppSetting.key == key)).scalar_one_or_none()
    if row:
        row.value = value
    else:
        db.add(AppSetting(key=key, value=value))
    db.commit()


def _get_recipe(db: Session, recipe_id: int) -> Recipe:
    recipe = db.get(Recipe, recipe_id)
    if not recipe:
        raise HTTPException(404, "Recept niet gevonden")
    return recipe


def _save_food_photo(recipe_id: int, data: bytes) -> bool:
    try:
        img = ImageOps.exif_transpose(Image.open(io.BytesIO(data)))
        if img.mode in ("RGBA", "P"):
            img = img.convert("RGB")
        img.thumbnail((1600, 1600), Image.LANCZOS)
        os.makedirs(IMAGE_DIR, exist_ok=True)
        img.save(os.path.join(IMAGE_DIR, f"{recipe_id}.jpg"), format="JPEG", quality=85)
        return True
    except Exception as e:
        logger.warning("Could not save food photo: %s", e)
        return False


# ── Pages ──────────────────────────────────────────────────────────────


@router.get("/", response_class=HTMLResponse)
async def today_page(request: Request, db: Session = Depends(get_db)):
    """Gezinsweergave: wat staat er vandaag en deze week op het menu."""
    from app.api.plan import entries_json, next_week_status

    monday = monday_of(date.today())
    entries = entries_json(db, planning.week_entries(db, monday))
    days = []
    for i in range(7):
        d = monday + timedelta(days=i)
        days.append({"label": day_label(d), "entries": [e for e in entries if e["date"] == str(d)],
                     "today": d == date.today()})
    return templates.TemplateResponse(request, "today.html", {"days": days, "nws": next_week_status(db)})


@router.get("/recepten", response_class=HTMLResponse)
async def recipes_page(request: Request, foto: str = "", db: Session = Depends(get_db)):
    recipes = db.execute(select(Recipe).order_by(Recipe.name)).scalars().all()
    without_photo = [r for r in recipes if not r.image_url]
    missing = sum(1 for r in recipes for i in r.ingredients
                  if not (i.get("skip") or i.get("auto_skip") or (i.get("product") or {}).get("id")))
    return templates.TemplateResponse(
        request, "recipes.html",
        {"recipes": without_photo if foto == "nee" else recipes, "no_photo_filter": foto == "nee",
         "no_photo_count": len(without_photo), "missing_count": missing, "has_api_key": bool(settings.anthropic_api_key)},
    )


@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse(request, "login.html", {"error": ""})


@router.post("/login")
async def login(request: Request, pin: str = Form("")):
    from app.main import session_token

    if settings.app_pin and hmac.compare_digest(pin.strip(), settings.app_pin):
        resp = RedirectResponse("/", status_code=303)
        resp.set_cookie("session", session_token(), max_age=60 * 60 * 24 * 365,
                        httponly=True, samesite="lax")
        return resp
    await asyncio.sleep(1)  # slow down guessing
    return templates.TemplateResponse(request, "login.html", {"error": "Pincode klopt niet."}, status_code=401)


@router.get("/recipe/{recipe_id}", response_class=HTMLResponse)
async def recipe_detail(request: Request, recipe_id: int, db: Session = Depends(get_db)):
    recipe = _get_recipe(db, recipe_id)
    await ensure_matched(db, recipe)
    return templates.TemplateResponse(
        request, "recipe_detail.html", {"recipe": recipe,
            "ingredients": recipe.ingredients,
            "has_token": bool(_get_setting(db, "ah_refresh_token") or _get_setting(db, "ah_user_token")),
        },
    )


@router.get("/recipe/{recipe_id}/koken", response_class=HTMLResponse)
async def cook_mode(request: Request, recipe_id: int, db: Session = Depends(get_db)):
    recipe = _get_recipe(db, recipe_id)
    return templates.TemplateResponse(request, "cook.html", {"recipe": recipe})


class GlutenPayload(BaseModel):
    gf_mode: str
    gf_note: str = ""
    ingredients: list[dict]


@router.post("/api/recipe/{recipe_id}/gluten")
async def save_gluten(recipe_id: int, payload: GlutenPayload, db: Session = Depends(get_db)):
    if payload.gf_mode not in ("none", "extra", "replace"):
        return JSONResponse({"ok": False, "error": "Ongeldige glutenvrij-modus"}, status_code=400)
    recipe = _get_recipe(db, recipe_id)
    recipe.gf_mode = payload.gf_mode
    recipe.gf_note = payload.gf_note
    recipe.ingredients = payload.ingredients
    db.commit()
    return {"ok": True}


@router.post("/api/recipe/{recipe_id}/gluten-suggest")
async def gluten_suggest(recipe_id: int, db: Session = Depends(get_db)):
    """Let Claude mark gluten ingredients and propose a gluten-free alternative per ingredient."""
    recipe = _get_recipe(db, recipe_id)
    ingredients = recipe.ingredients
    try:
        result = await suggest_gluten_free(recipe.name, [i["text"] for i in ingredients])
    except Exception as e:
        logger.error("Gluten-free suggestion failed: %s", e)
        return JSONResponse({"ok": False, "error": str(e)}, status_code=500)
    for idx, ing in enumerate(ingredients):
        ing["gluten"] = idx in result["items"]
        ing["gf_search"] = result["items"].get(idx, "")
        ing["gf_product"] = None
    recipe.ingredients = ingredients
    recipe.gf_mode = result["mode"] if result["items"] else "none"
    recipe.gf_note = result["note"]
    db.commit()
    return {"ok": True, "gf_mode": recipe.gf_mode, "gf_note": recipe.gf_note, "ingredients": ingredients}


@router.get("/image/{recipe_id}")
async def recipe_image(recipe_id: int):
    path = os.path.join(IMAGE_DIR, f"{int(recipe_id)}.jpg")
    if not os.path.exists(path):
        raise HTTPException(404)
    return FileResponse(path, headers={"Cache-Control": "public, max-age=86400"})


@router.post("/api/recipe/{recipe_id}/photo")
async def replace_photo(recipe_id: int, photo: UploadFile | None = File(default=None),
                        image_url: str = Form(""), db: Session = Depends(get_db)):
    """Vervang de gerechtfoto: een geüploade foto, of een foto-URL die de server zelf ophaalt."""
    recipe = _get_recipe(db, recipe_id)
    data = await photo.read() if photo and photo.filename else None
    if photo and photo.filename and photo.content_type not in ALLOWED_IMAGE_TYPES:
        return JSONResponse({"ok": False, "error": f"Ongeldig bestandstype: {photo.content_type}"}, status_code=400)
    if not data and image_url.strip():
        data = await fetch_image(image_url.strip())
    if not data:
        return JSONResponse({"ok": False, "error": "Geen foto ontvangen."}, status_code=400)
    if len(data) > 15 * 1024 * 1024 or not _save_food_photo(recipe.id, data):
        return JSONResponse({"ok": False, "error": "Deze foto kon niet worden opgeslagen."}, status_code=400)
    recipe.image_url = f"/image/{recipe.id}?v={int(time.time())}"  # nieuwe URL: oude foto staat nog in caches
    db.commit()
    return {"ok": True, "image_url": recipe.image_url}


@router.post("/api/recipe/{recipe_id}/photo/remove")
async def remove_photo(recipe_id: int, db: Session = Depends(get_db)):
    """Haal een foto weg die geen gerecht laat zien; het recept komt dan bij 'Zonder foto'."""
    recipe = _get_recipe(db, recipe_id)
    path = os.path.join(IMAGE_DIR, f"{recipe.id}.jpg")
    if os.path.exists(path):
        os.remove(path)
    recipe.image_url = ""
    db.commit()
    return {"ok": True}


# ── Import (URL / tekst / foto's) ──────────────────────────────────────


async def fetch_image(url: str) -> bytes | None:
    """Haal alleen een receptfoto op (geen pagina). Faalt stil."""
    from app.clients.extractor import _check_public_url

    try:
        _check_public_url(url)
        async with httpx.AsyncClient(follow_redirects=True, timeout=15) as client:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0 (compatible; Miso/1.0)"})
        if resp.status_code == 200 and resp.headers.get("content-type", "").startswith("image/"):
            return resp.content
        logger.warning("Recipe photo %s: HTTP %s", url[:120], resp.status_code)
    except Exception as e:  # noqa: BLE001
        logger.warning("Recipe photo %s failed: %s", url[:120], e)
    return None


async def store_photo_locally(db: Session, recipe: Recipe) -> bool:
    """Externe foto-link (receptsite, Allerhande) eenmalig ophalen en zelf bewaren: werkt dan ook als de site
    de link verandert of hotlinken blokkeert."""
    if not (recipe.image_url or "").startswith(("http://", "https://")):
        return False
    data = await fetch_image(recipe.image_url)
    if data and len(data) <= 15 * 1024 * 1024 and _save_food_photo(recipe.id, data):
        recipe.image_url = f"/image/{recipe.id}"
        db.commit()
        return True
    return False


def fetch_error_text(e: Exception) -> str:
    """Begrijpelijke melding als een receptsite niet op te halen is."""
    status = getattr(getattr(e, "response", None), "status_code", None)
    if status in (401, 403, 429, 503):
        return ("Deze website laat Miso niet meelezen. Deel het recept vanuit Safari of Chrome naar Miso, "
                "plak de recepttekst hier, of kies screenshots van het recept.")
    if status == 404:
        return "Deze pagina bestaat niet (meer). Controleer de link."
    return ("De website was niet bereikbaar. Probeer het later nog eens, of plak de recepttekst / "
            "kies screenshots van het recept.")


@router.post("/api/import")
async def import_recipe(
    url: str = Form(""),
    text: str = Form(""),
    images: list[UploadFile] = File(default=[]),
    source_url: str = Form(""),  # bronlink die alleen wordt bewaard, niet opgehaald (deelknop)
    image_url: str = Form(""),  # foto van het recept op de site (deelknop); server haalt alleen de foto op
    photo: UploadFile | None = File(default=None),  # foto die het toestel al heeft gedownload
    db: Session = Depends(get_db),
):
    url, text = url.strip(), text.strip()
    source_url, shared_image_url = source_url.strip(), image_url.strip()
    image_list: list[tuple[bytes, str]] = []
    for img in images:
        if not img.filename:
            continue
        if img.content_type not in ALLOWED_IMAGE_TYPES:
            return JSONResponse({"ok": False, "error": f"Ongeldig bestandstype: {img.content_type}"}, status_code=400)
        data = await img.read()
        if len(data) > 20 * 1024 * 1024:
            return JSONResponse({"ok": False, "error": "Afbeelding is te groot (max 20MB)."}, status_code=400)
        image_list.append((data, img.content_type))

    if not (url or text or image_list):
        return JSONResponse({"ok": False, "error": "Geef een URL, tekst of foto's op."}, status_code=400)

    try:
        image_url = ""
        if url:
            page_text, image_url = await fetch_url(url)
            text = f"{text}\n\n{page_text}" if text else page_text
        raw = await extract_recipe(text=text or None, images=image_list or None)
    except httpx.HTTPError as e:
        logger.error("Fetching %s failed: %s", url, e)
        return JSONResponse({"ok": False, "error": fetch_error_text(e)}, status_code=502)
    except Exception as e:
        logger.error("Recipe import failed: %s", e)
        return JSONResponse({"ok": False, "error": str(e)}, status_code=500)

    recipe = Recipe(
        name=raw["name"], description=raw["description"], servings=raw["servings"],
        total_time=raw["total_time"], source_url=url or source_url, image_url=image_url,
    )
    recipe.ingredients = raw["ingredients"]
    recipe.instructions = raw["instructions"]
    db.add(recipe)
    db.commit()

    idx = raw.get("food_photo_index")
    if isinstance(idx, int) and 0 <= idx < len(image_list):
        if _save_food_photo(recipe.id, image_list[idx][0]):
            recipe.image_url = f"/image/{recipe.id}"
            db.commit()

    if not recipe.image_url:  # foto van de deelknop: eerst wat het toestel stuurde, anders zelf de foto ophalen
        data = await photo.read() if photo and photo.filename else None
        if not data and shared_image_url:
            data = await fetch_image(shared_image_url)
        if data and len(data) <= 15 * 1024 * 1024 and _save_food_photo(recipe.id, data):
            recipe.image_url = f"/image/{recipe.id}"
            db.commit()

    await store_photo_locally(db, recipe)
    from app.maintenance import profile_later

    profile_later(recipe.id)
    logger.info("Imported recipe %s (id=%s)", recipe.name, recipe.id)
    return {"ok": True, "id": recipe.id, "name": recipe.name}


def remove_recipe(db: Session, recipe: Recipe) -> None:
    """Recept weg, met alles wat ernaar verwijst (planregels, gezondheidsprofiel, foto)."""
    from app.models import FreezerItem, RecipeProfile

    rid = recipe.id
    for entry in db.execute(select(PlanEntry).where(PlanEntry.recipe_id == rid)).scalars():
        db.delete(entry)
    for prof in db.execute(select(RecipeProfile).where(RecipeProfile.recipe_id == rid)).scalars():
        db.delete(prof)
    for item in db.execute(select(FreezerItem).where(FreezerItem.from_recipe_id == rid)).scalars():
        item.from_recipe_id = None  # de porties liggen nog in de vriezer
    db.delete(recipe)
    db.commit()
    path = os.path.join(IMAGE_DIR, f"{rid}.jpg")
    if os.path.exists(path):
        os.remove(path)


@router.post("/recipe/{recipe_id}/delete")
async def delete_recipe(recipe_id: int, db: Session = Depends(get_db)):
    remove_recipe(db, _get_recipe(db, recipe_id))
    return RedirectResponse("/recepten", status_code=303)


# ── AH producten ───────────────────────────────────────────────────────


@router.get("/api/ah/search")
async def ah_search(q: str = Query(..., min_length=1)):
    try:
        return {"products": await ah_client.search_products(q, size=8)}
    except Exception as e:
        logger.error("AH search failed: %s", e)
        return {"products": [], "error": str(e)}


class IngredientsPayload(BaseModel):
    ingredients: list[dict]


@router.post("/api/recipe/{recipe_id}/ingredients")
async def save_ingredients(recipe_id: int, payload: IngredientsPayload, db: Session = Depends(get_db)):
    recipe = _get_recipe(db, recipe_id)
    old = {i.get("text"): (i.get("product") or {}).get("id") for i in recipe.ingredients}
    new = payload.ingredients
    for ing in new:
        pid = (ing.get("product") or {}).get("id")
        if pid and old.get(ing.get("text")) != pid:
            ing["manual"] = True  # door de gebruiker gekozen: niet meer automatisch overschrijven
            ing["source"] = "handmatig"
            learn_pref(db, ing)  # en onthouden voor andere recepten
            need, pack = needed(ing.get("text", "")), pack_size((ing["product"] or {}).get("unit_size", ""))
            ing["quantity"] = packs_for(need, pack) or ing.get("quantity") or 1
    recipe.ingredients = new
    db.commit()
    return {"ok": True}


def load_prefs(db: Session) -> dict[str, dict]:
    """Geleerde productkeuzes per zoekterm (uit handmatige correcties van het gezin)."""
    return {p.term: json.loads(p.product_json) for p in db.execute(select(ProductPreference)).scalars()}


def learn_pref(db: Session, ing: dict) -> None:
    term = query_terms(ing.get("search") or ing.get("text", ""))[0]
    if not term or not ing.get("product"):
        return
    row = db.execute(select(ProductPreference).where(ProductPreference.term == term)).scalar_one_or_none()
    product = {k: v for k, v in ing["product"].items() if k != "image_url"} | {"image_url": ing["product"].get("image_url", "")}
    if row:
        row.product_json, row.uses = json.dumps(product, ensure_ascii=False), row.uses + 1
    else:
        db.add(ProductPreference(term=term, product_json=json.dumps(product, ensure_ascii=False)))


async def find_product(term: str, text: str = "", sem: asyncio.Semaphore | None = None) -> dict | None:
    """Zoek het beste AH-product voor een ingrediënt (zelfde regels als het automatisch koppelen)."""
    sem = sem or asyncio.Semaphore(4)
    # De volledige regel bevat meer informatie ("1/2 tl paprika" = poeder) dan Mealie's naam ("paprika")
    query, _, flags = query_terms(text) if text and query_terms(text)[0] else query_terms(term)
    need = needed(text or term)
    if not query:
        return None
    products: list[dict] = []
    seen: set = set()
    for q in search_queries(query, flags):
        async with sem:
            try:
                found = await ah_client.search_products(q, size=20)
            except Exception as e:
                logger.warning("AH search failed for %s: %s", q, e)
                continue
        for p in found:
            key = (p.get("id"), p.get("name"), p.get("unit_size"))  # multipacks delen soms het id
            if key not in seen:
                seen.add(key)
                products.append(p)
    return choose(products, query, flags, need)


async def match_extras(db: Session, extras: list[dict]) -> list[dict]:
    """Koppel vrije-tekst-boodschappen ("pasta", "parmezaan") aan AH-producten. Altijd aantal 1;
    basisvoorraad wordt hier niet overgeslagen: wie het opschrijft, wil het kopen."""
    prefs = load_prefs(db)
    sem = asyncio.Semaphore(4)

    async def one(extra: dict) -> dict:
        text = (extra.get("text") or "").strip()
        if not text or (extra.get("product") or {}).get("id"):
            return {"text": text, "product": extra.get("product")}
        learned = prefs.get(query_terms(text)[0])
        try:
            product = dict(learned) if learned else await asyncio.wait_for(find_product(text, text, sem), timeout=20)
        except Exception as e:  # noqa: BLE001 - zonder AH blijft de regel gewoon open staan
            logger.warning("Matching extra %r failed: %s", text, e)
            product = None
        return {"text": text, "product": product}

    return list(await asyncio.gather(*(one(x) for x in extras)))


async def _automatch(ingredients: list[dict], gluten_free: bool = False, force: bool = False,
                     prefs: dict[str, dict] | None = None) -> int:
    """Koppel ingrediënten aan AH-producten: biologisch > huismerk, basisspullen overslaan, aantal
    verpakkingen berekenen. Handmatig gekozen producten blijven staan."""
    sem = asyncio.Semaphore(4)

    async def find(term: str, text: str = "") -> dict | None:
        return await find_product(term, text, sem)

    def apply_quantity(ing: dict, product: dict) -> None:
        need = needed(ing.get("text", ""))
        pack = pack_size(product.get("unit_size", ""))
        packs = packs_for(need, pack)
        ing["need"] = need if packs is not None else None
        ing["pack"] = pack if packs is not None else None
        n_stuk = need and need["unit"] == "stuk" and pack is None and not re.search(r"\b(zakje|zakjes)\b", ing.get("text", "").lower())
        small_tub = re.search(r"siroop|saus|dressing|mayonaise|ketchup|pesto|olie|azijn|honing", ing.get("text", "").lower())
        big = pack and pack["unit"] in ("g", "ml") and pack["amount"] >= (100 if small_tub else 400)  # sauskuipje ~25 ml
        containers = container_count(ing.get("text", ""))
        if containers and big and re.search(r"\b(kuipjes?|bekertjes?|potjes?)\b", ing.get("text", "").lower()):
            containers = 1  # "2 kuipjes yoghurt" is geen 2 liter
        ing["quantity"] = packs or containers or (
            max(1, math.ceil(need["amount"] - 1e-9)) if n_stuk and need["amount"] <= 12 and not str(product.get("unit_size", "")).strip().endswith(("g", "kg", "ml", "l")) else 1)

    async def match(ing: dict) -> int:
        if ing.get("skip") and not ing.get("auto_skip"):
            return 0
        n = 0
        stale = ing.get("match_v") != MATCH_VERSION and not ing.get("manual")
        if ing.get("auto_skip") and not (force or stale):
            return 0
        search = ing.get("search") or ing.get("text", "")
        text = ing.get("text", "").strip()
        if (not clean_search(search) or text.startswith("*") or text.endswith(":") or len(text.split()) > 12
                or is_pantry(search, ing.get("text", "")) or is_equipment(search, ing.get("text", ""))
                or has_no_product(search)):
            ing.update(skip=True, auto_skip=True, product=None, match_v=MATCH_VERSION)
            return 0
        if ing.get("auto_skip"):
            ing.update(skip=False, auto_skip=False)
        if search and (not ing.get("product") or ((force or stale) and not ing.get("manual"))):
            learned = (prefs or {}).get(query_terms(search)[0])
            product = dict(learned) if learned else await find(search, ing.get("text", ""))
            if product:
                ing["product"], n = product, n + 1
                ing["source"] = "geleerd" if learned else "auto"
                apply_quantity(ing, product)
            elif ing.get("product") and not ing.get("manual"):
                # Niets gevonden. Klopt de oude koppeling volgens de nieuwe regels nog, dan blijft hij staan
                # (AH-zoeken geeft soms tijdelijk niets terug); anders was hij fout en gaat hij weg.
                q, _, fl = query_terms(text or search)
                if max(score(ing["product"], q, fl, needed(text or search), relaxed) for relaxed in (False, True)) >= 30:
                    apply_quantity(ing, ing["product"])
                else:
                    ing["product"] = None
                    ing.pop("source", None)
            ing["match_v"] = MATCH_VERSION
        if gluten_free and ing.get("gluten") and not ing.get("gf_product") and ing.get("gf_search"):
            product = await find(ing["gf_search"])
            if product:
                ing["gf_product"], n = product, n + 1
        return n

    return sum(await asyncio.gather(*(match(i) for i in ingredients)))


async def ensure_matched(db: Session, recipe: Recipe) -> None:
    """Koppel ontbrekende of verouderde matches automatisch zodra een recept geopend wordt."""
    ingredients = recipe.ingredients
    todo = [i for i in ingredients if not i.get("manual") and i.get("match_v") != MATCH_VERSION]
    if not todo:
        return
    try:
        await asyncio.wait_for(_automatch(ingredients, recipe.gf_mode != "none", prefs=load_prefs(db)), timeout=25)
    except Exception as e:  # noqa: BLE001
        logger.warning("Auto-match for recipe %s failed: %s", recipe.id, e)
        return
    recipe.ingredients = ingredients
    db.commit()


@router.post("/api/recipe/{recipe_id}/automatch")
async def automatch(recipe_id: int, force: bool = False, db: Session = Depends(get_db)):
    recipe = _get_recipe(db, recipe_id)
    ingredients = recipe.ingredients
    matched = await _automatch(ingredients, recipe.gf_mode != "none", force=force, prefs=load_prefs(db))
    recipe.ingredients = ingredients
    db.commit()
    return {"ok": True, "matched": matched, "ingredients": ingredients}


# ── Weekmenu ───────────────────────────────────────────────────────────


def _locked_key(week_start: date) -> str:
    return f"locked:{week_start}"


def _week_recipes(db: Session, week_start: date) -> list[Recipe]:
    """Recipes cooked in a week (kind "recipe"); a recipe planned twice appears twice. Unscaled:
    for groceries use `week_cart`."""
    return planning.week_grocery_input(db, week_start)[0]


def _pushed(db: Session, week_start: date) -> dict[int, int]:
    rows = db.execute(select(CartPush).where(CartPush.week_start == str(week_start))).scalars()
    return {r.product_id: r.quantity for r in rows}


def week_status(db: Session, week_start: date) -> dict:
    """Compare what the week needs with what we already put on the AH list."""
    cart, unmatched = week_cart(db, week_start)
    pushed = _pushed(db, week_start)
    missing = [
        {"name": item["name"], "quantity": item["quantity"] - pushed.get(item["product_id"], 0)}
        for item in cart
        if item["quantity"] > pushed.get(item["product_id"], 0)
    ]
    return {
        "needed": len(cart),
        "missing": missing,
        "missing_count": len(missing),
        "unmatched": unmatched,
        "complete": bool(cart) and not missing and not unmatched,
        "on_list": sum(1 for item in cart if pushed.get(item["product_id"], 0) >= item["quantity"]),
        "locked": _get_setting(db, _locked_key(week_start)) == "1",
    }


@router.get("/weekmenu", response_class=HTMLResponse)
async def weekmenu_page(request: Request, week: str | None = None, db: Session = Depends(get_db)):
    from app.api.plan import entries_json, next_week_status

    monday = parse_week(week)
    has_recipes = db.query(Recipe).count() > 0
    days = [{"date": str(monday + timedelta(days=i)), "label": day_label(monday + timedelta(days=i))} for i in range(7)]
    return templates.TemplateResponse(
        request, "weekmenu.html",
        {
            "week": str(monday),
            "prev_week": str(monday - timedelta(days=7)),
            "next_week": str(monday + timedelta(days=7)),
            "has_recipes": has_recipes,
            "days": days,
            "entries": entries_json(db, planning.week_entries(db, monday)),
            "household": planning.household_size(db),
            "status": week_status(db, monday),
            "nws": next_week_status(db),
            "today": str(date.today()),
            "has_token": bool(_get_setting(db, "ah_refresh_token") or _get_setting(db, "ah_user_token")),
        },
    )


@router.get("/kiezen", response_class=HTMLResponse)
async def choose_page(request: Request, week: str | None = None, db: Session = Depends(get_db)):
    """Wat eten we? Recepten zoeken en kiezen -> inplannen -> boodschappen naar AH."""
    recipes = db.execute(select(Recipe).order_by(Recipe.name)).scalars().all()
    return templates.TemplateResponse(
        request, "kiezen.html",
        {
            "recipes": [{"id": r.id, "name": r.name, "image_url": r.image_url or "", "servings": r.servings or "",
                         "total_time": r.total_time or "", "ah_recipe_id": r.ah_recipe_id} for r in recipes],
            "week": str(parse_week(week)),
            "today": str(date.today()),
            "household": planning.household_size(db),
            "has_token": bool(_get_setting(db, "ah_refresh_token") or _get_setting(db, "ah_user_token")),
        },
    )


class PlanPayload(BaseModel):
    week: str
    days: dict[str, list[int]]  # ISO date -> recipe ids


@router.post("/api/plan")
async def save_plan(payload: PlanPayload, db: Session = Depends(get_db)):
    """Oude (iOS) API: de recepten per dag van een week. Werkt als verschil op de recept-regels, zodat
    personen, restjes en voorraad-dagen (die de oude app niet kent) blijven staan."""
    monday = parse_week(payload.week)
    valid = {str(monday + timedelta(days=i)) for i in range(7)}
    existing: dict[str, list[PlanEntry]] = {}
    for entry in db.execute(select(PlanEntry).where(PlanEntry.date.in_(valid), PlanEntry.kind == "recipe")
                            .order_by(PlanEntry.id)).scalars():
        existing.setdefault(entry.date, []).append(entry)
    for day in valid:
        wanted = [rid for rid in payload.days.get(day, []) if db.get(Recipe, rid)]
        keep: list[PlanEntry] = []
        for entry in existing.get(day, []):
            if entry.recipe_id in wanted:
                wanted.remove(entry.recipe_id)
                keep.append(entry)
            else:
                for leftover in planning.leftovers_of(db, entry.id):
                    db.delete(leftover)
                db.delete(entry)
        for rid in wanted:
            db.add(PlanEntry(date=day, recipe_id=rid, kind="recipe"))
    db.commit()
    return {"ok": True, "status": week_status(db, monday)}


class WeekPayload(BaseModel):
    week: str
    locked: bool | None = None


@router.post("/api/plan/sync")
async def sync_week(payload: WeekPayload, db: Session = Depends(get_db)):
    """Put everything the week still needs on the AH list and report if the week is complete.

    With `locked` set, the week is also locked ("vastgezet") or unlocked.
    """
    monday = parse_week(payload.week)
    if payload.locked is False:
        _set_setting(db, _locked_key(monday), "0")
        return {"ok": True, "status": week_status(db, monday)}

    recipes, factors, extras = planning.week_grocery_input(db, monday)
    if not recipes and not extras:
        return {"ok": False, "error": "Er staan nog geen recepten in deze week."}
    for recipe in {r.id: r for r in recipes}.values():
        ingredients = recipe.ingredients
        if await _automatch(ingredients, recipe.gf_mode != "none", prefs=load_prefs(db)):
            recipe.ingredients = ingredients
    for entry in planning.week_entries(db, monday):  # extra's die nog geen AH-product hebben
        if entry.kind == "stock" and any(not (x.get("product") or {}).get("id") for x in entry.extras):
            entry.extras = await match_extras(db, entry.extras)
    db.commit()

    cart, _ = week_cart(db, monday)
    pushed = _pushed(db, monday)
    delta = [
        {**item, "quantity": item["quantity"] - pushed.get(item["product_id"], 0)}
        for item in cart
        if item["quantity"] > pushed.get(item["product_id"], 0)
    ]
    added = 0
    if delta:
        access_token = _get_setting(db, "ah_user_token")
        refresh_token = _get_setting(db, "ah_refresh_token")
        if not access_token and not refresh_token:
            return {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}

        def _save_tokens(new_access: str, new_refresh: str) -> None:
            _set_setting(db, "ah_user_token", new_access)
            _set_setting(db, "ah_refresh_token", new_refresh)

        ah_client.set_user_tokens(access_token, refresh_token, on_tokens_updated=_save_tokens)
        try:
            await ah_client.add_to_cart(delta)
        except Exception as e:
            logger.error("Failed to fill AH list for week %s: %s", monday, e)
            return {"ok": False, "error": str(e)}
        rows = {r.product_id: r for r in db.execute(select(CartPush).where(CartPush.week_start == str(monday))).scalars()}
        for item in delta:
            row = rows.get(item["product_id"])
            if row:
                row.quantity += item["quantity"]
            else:
                db.add(CartPush(week_start=str(monday), product_id=item["product_id"],
                                quantity=item["quantity"], name=item["name"]))
        db.commit()
        added = len(delta)

    if payload.locked:
        _set_setting(db, _locked_key(monday), "1")
    return {"ok": True, "added": added, "status": week_status(db, monday)}


# ── Boodschappenlijstje van AH ─────────────────────────────────────────


class CartPayload(BaseModel):
    recipe_ids: list[int]
    persons: dict[str, int] = {}  # recipe id -> personen (leeg = huishoudgrootte)


def aggregate_cart(recipes: list[Recipe], factors: list[float] | None = None,
                   extras: list[dict] | None = None) -> tuple[list[dict], list[str]]:
    """Merge ingredients over recipes. Returns (cart items, unmatched ingredient texts).

    `factors[i]` scales recipe i (planned persons / recipe servings): comparable needs ("500 g") are
    multiplied before packs are counted (at least 1 pack); other quantities only go up from 1.5x.
    `extras` are free-text extra groceries ({"text", "product"}) bought once each.

    Gluten-free handling per recipe (`gf_mode`) for ingredients marked `gluten`:
    "extra" buys the gluten-free product on top of the normal one (for 1 person),
    "replace" buys only the gluten-free product (for everyone).
    """
    cart: dict[int, dict] = {}
    unmatched: list[str] = []

    totals: dict[int, dict] = {}  # product id -> {"amount", "unit", "pack", "ok"} voor slim optellen

    def add(product: dict, qty: int, ing: dict | None = None, factor: float = 1.0) -> None:
        pid = product["id"]
        if pid in cart:
            cart[pid]["quantity"] += qty
        else:
            cart[pid] = {"product_id": pid, "quantity": qty, "name": product.get("name", "")}
        need, pack = (ing or {}).get("need"), (ing or {}).get("pack")
        t = totals.setdefault(pid, {"amount": 0.0, "unit": None, "pack": None, "ok": True})
        if need and pack and t["unit"] in (None, need["unit"]) and need["unit"] == pack["unit"]:
            t.update(unit=need["unit"], pack=pack)
            t["amount"] += need["amount"] * factor
        else:
            t["ok"] = False

    factors = list(factors or [])
    for idx, recipe in enumerate(recipes):
        factor = factors[idx] if idx < len(factors) and factors[idx] else 1.0
        for ing in recipe.ingredients:
            if ing.get("skip"):
                continue
            text = ing.get("text", "")
            f = factor
            base = (ing.get("need") or {}).get("for_persons")
            if base:  # "per persoon" / HelloFresh-reeks: al voor `base` personen, niet voor het receptaantal
                f = factor * planning.recipe_servings(recipe) / base
            qty = planning.scale_quantity(int(ing.get("quantity") or 1), f)
            product = ing.get("product")
            has_product = bool(product and product.get("id"))
            gf = ing.get("gf_product")
            has_gf = bool(gf and gf.get("id"))

            if ing.get("gluten") and recipe.gf_mode == "replace":
                if has_gf:
                    add(gf, qty)  # geen vergelijkbare hoeveelheid: qty is al geschaald
                else:
                    unmatched.append(f"{text} (glutenvrij)")
                continue

            if has_product:
                add(product, qty, ing, f)
            else:
                unmatched.append(text)
            if ing.get("gluten") and recipe.gf_mode == "extra":
                if has_gf:
                    add(gf, 1)
                else:
                    unmatched.append(f"{text} (glutenvrij)")
    for pid, t in totals.items():
        if t["ok"] and t["pack"] and t["amount"]:
            cart[pid]["quantity"] = max(1, math.ceil(t["amount"] / t["pack"]["amount"] - 1e-9))
    for extra in extras or []:  # "hebben we al" + extra: altijd 1 stuk erbij
        product = extra.get("product") or {}
        if product.get("id"):
            pid = product["id"]
            if pid in cart:
                cart[pid]["quantity"] += 1
            else:
                cart[pid] = {"product_id": pid, "quantity": 1, "name": product.get("name", "")}
        elif (extra.get("text") or "").strip():
            unmatched.append(extra["text"].strip())
    return list(cart.values()), unmatched


def recipe_factors(db: Session, recipes: list[Recipe], persons: dict | None = None) -> list[float]:
    """Schaalfactor per recept voor losse recepten (kiezen/mandje): opgegeven personen of huishoudgrootte."""
    household = planning.household_size(db)
    persons = {str(k): v for k, v in (persons or {}).items()}
    out = []
    for r in recipes:
        try:
            p = int(persons.get(str(r.id)) or household)
        except (TypeError, ValueError):
            p = household
        out.append(planning.scale_factor(max(1, min(planning.MAX_PERSONS, p)), r))
    return out


def week_cart(db: Session, week_start: date) -> tuple[list[dict], list[str]]:
    """Boodschappen voor een week: recepten geschaald op personen (+ dubbel koken), plus extra's."""
    return aggregate_cart(*planning.week_grocery_input(db, week_start))


@router.post("/api/cart/fill")
async def fill_cart(payload: CartPayload, db: Session = Depends(get_db)):
    recipes = [r for r in (db.get(Recipe, i) for i in dict.fromkeys(payload.recipe_ids)) if r]
    if not recipes:
        return {"ok": False, "error": "Geen recepten gekozen."}

    # Match whatever is still unmatched so a one-click flow works
    for recipe in recipes:
        ingredients = recipe.ingredients
        if await _automatch(ingredients, recipe.gf_mode != "none", prefs=load_prefs(db)):
            recipe.ingredients = ingredients
    db.commit()

    cart, unmatched = aggregate_cart(recipes, recipe_factors(db, recipes, payload.persons))
    if not cart:
        return {"ok": False, "error": "Geen AH-producten gevonden voor deze ingrediënten."}

    access_token = _get_setting(db, "ah_user_token")
    refresh_token = _get_setting(db, "ah_refresh_token")
    if not access_token and not refresh_token:
        return {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}

    def _save_tokens(new_access: str, new_refresh: str) -> None:
        _set_setting(db, "ah_user_token", new_access)
        _set_setting(db, "ah_refresh_token", new_refresh)

    ah_client.set_user_tokens(access_token, refresh_token, on_tokens_updated=_save_tokens)
    try:
        await ah_client.add_to_cart(cart)
    except Exception as e:
        logger.error("Failed to fill AH list: %s", e)
        return {"ok": False, "error": str(e)}
    return {"ok": True, "items_added": len(cart), "unmatched": unmatched}


# ── AH-recepten (Allerhande) ───────────────────────────────────────────


@router.post("/api/allerhande/add")
async def allerhande_add(recipe_id: int = Form(...), db: Session = Depends(get_db)):
    result = await import_allerhande_recipe(db, recipe_id)
    if not result["ok"]:
        return JSONResponse({"ok": False, "error": result["error"]}, status_code=result["status"])
    return {"ok": True, "id": result["id"]}


async def import_allerhande_recipe(db: Session, recipe_id: int) -> dict:
    """Allerhande-recept opslaan (dedupe op ah_recipe_id). {"ok", "id", "new"} of {"ok": False, "error", "status"}."""
    existing = db.execute(select(Recipe).where(Recipe.ah_recipe_id == recipe_id)).scalar_one_or_none()
    if existing:
        return {"ok": True, "id": existing.id, "new": False}
    try:
        data = convert_ah_recipe(await ah_client.get_recipe(recipe_id))
    except Exception as e:
        logger.error("Fetching Allerhande recipe %s failed: %s", recipe_id, e)
        return {"ok": False, "error": f"Recept ophalen mislukt: {e}", "status": 502}
    if not data["name"] or not data["ingredients"]:
        return {"ok": False, "error": "Dit recept bevat geen ingrediënten.", "status": 422}

    recipe = Recipe(
        name=data["name"], description=data["description"], servings=data["servings"],
        total_time=data["total_time"], ah_recipe_id=recipe_id,
        source_url=f"https://www.ah.nl/allerhande/recept/R-R{recipe_id}", image_url=data.get("image_url", ""),
    )
    recipe.ingredients = data["ingredients"]
    recipe.instructions = data["instructions"]
    db.add(recipe)
    db.commit()
    await store_photo_locally(db, recipe)
    from app.maintenance import profile_later

    profile_later(recipe.id)
    logger.info("Added Allerhande recipe %s (id=%s)", recipe.name, recipe.id)
    return {"ok": True, "id": recipe.id, "new": True}


# ── Import uit Mealie ──────────────────────────────────────────────────


@router.post("/settings/mealie")
async def import_from_mealie(
    request: Request,
    mealie_url: str = Form(""),
    mealie_token: str = Form(""),
    db: Session = Depends(get_db),
):
    url = mealie_url.strip() or _get_setting(db, "mealie_url")
    token = mealie_token.strip() or _get_setting(db, "mealie_token")
    if not url:
        return _render_settings(request, db, mealie_error="Vul de URL van Mealie in.")
    if not url.startswith(("http://", "https://")):
        return _render_settings(request, db, mealie_error="De URL moet met http:// of https:// beginnen.")
    _set_setting(db, "mealie_url", url)
    _set_setting(db, "mealie_token", token)

    mealie = MealieClient(url, token)
    imported = skipped = failed = 0
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            slugs = await mealie.list_slugs(client)
            existing = set(db.execute(select(Recipe.mealie_slug).where(Recipe.mealie_slug.is_not(None))).scalars())
            for slug in slugs:
                if slug in existing:
                    skipped += 1
                    continue
                try:
                    full = await mealie.get_recipe(client, slug)
                    data = convert_recipe(full)
                    if not data["name"] or not data["ingredients"]:
                        failed += 1
                        continue
                    recipe = Recipe(
                        name=data["name"], description=data["description"], servings=data["servings"],
                        total_time=data["total_time"], source_url=data["source_url"], mealie_slug=slug,
                    )
                    recipe.ingredients = data["ingredients"]
                    recipe.instructions = data["instructions"]
                    db.add(recipe)
                    db.commit()
                    if full.get("id"):
                        image = await mealie.get_image(client, full["id"])
                        if image and _save_food_photo(recipe.id, image):
                            recipe.image_url = f"/image/{recipe.id}"
                            db.commit()
                    imported += 1
                except Exception as e:
                    db.rollback()
                    logger.warning("Importing Mealie recipe %s failed: %s", slug, e)
                    failed += 1
    except httpx.HTTPStatusError as e:
        msg = f"Mealie gaf een fout (HTTP {e.response.status_code}). Controleer URL en token."
        return _render_settings(request, db, mealie_error=msg)
    except httpx.HTTPError as e:
        return _render_settings(request, db, mealie_error=f"Mealie niet bereikbaar: {e}")

    msg = f"{imported} recepten geïmporteerd, {skipped} stonden er al" + (f", {failed} mislukt." if failed else ".")
    logger.info("Mealie import: %s", msg)
    return _render_settings(request, db, mealie_result=msg)


# ── Instellingen ───────────────────────────────────────────────────────


@router.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request, db: Session = Depends(get_db)):
    return _render_settings(request, db)


@router.post("/settings/plan")
async def save_plan_settings(request: Request, household_size: int = Form(...), order_weekday: int = Form(...),
                             db: Session = Depends(get_db)):
    if not (1 <= household_size <= planning.MAX_PERSONS and 0 <= order_weekday <= 6):
        return _render_settings(request, db, plan_result="Kies 1 tot 20 personen en een dag van de week.")
    planning.set_setting(db, "household_size", str(household_size))
    planning.set_setting(db, "order_weekday", str(order_weekday))
    return _render_settings(request, db, plan_result="Opgeslagen.")


@router.post("/settings/ah-code")
async def ah_code_exchange(request: Request, callback_url: str = Form(""), db: Session = Depends(get_db)):
    raw = callback_url.strip()
    if not raw:
        return _render_settings(request, db, ah_login_error="Plak de URL uit je adresbalk.")
    try:
        code = parse_qs(urlparse(raw).query).get("code", [None])[0]
    except Exception:
        code = None
    code = code or raw
    try:
        data = await ah_client.exchange_code(code)
        _set_setting(db, "ah_user_token", data["access_token"])
        _set_setting(db, "ah_refresh_token", data["refresh_token"])
        return _render_settings(request, db, ah_login_success=True)
    except httpx.HTTPStatusError as e:
        msg = f"Code ongeldig of verlopen (HTTP {e.response.status_code}). Probeer opnieuw."
        return _render_settings(request, db, ah_login_error=msg)
    except Exception as e:
        return _render_settings(request, db, ah_login_error=f"Koppelen mislukt: {e}")


def _render_settings(
    request: Request,
    db: Session,
    ah_login_error: str = "",
    ah_login_success: bool = False,
    mealie_error: str = "",
    mealie_result: str = "",
    plan_result: str = "",
):
    return templates.TemplateResponse(
        request, "settings.html", {"ah_token_set": bool(_get_setting(db, "ah_user_token")),
            "household_size": planning.household_size(db),
            "order_weekday": planning.order_weekday(db),
            "weekdays": planning.WEEKDAYS,
            "plan_result": plan_result,
            "ah_refresh_set": bool(_get_setting(db, "ah_refresh_token")),
            "has_api_key": bool(settings.anthropic_api_key),
            "ah_login_url": ah_client.get_login_url(),
            "ah_login_error": ah_login_error,
            "ah_login_success": ah_login_success,
            "mealie_url": _get_setting(db, "mealie_url"),
            "mealie_token_set": bool(_get_setting(db, "mealie_token")),
            "mealie_error": mealie_error,
            "mealie_result": mealie_result,
        },
    )
