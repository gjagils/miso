"""AH-gegevens in Miso: bonus -> receptsuggesties, AH-lijsten, Allerhande-favorieten, standaardboodschappen.

Elke AH-fout geeft `{"ok": false, "error": "<Nederlandse melding>"}` (HTTP 200), zodat de UI de sectie
gewoon verbergt. Hier wordt nooit een bestelling geplaatst; alleen gelezen en het lijstje gevuld.
"""

import json
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import ah_sync
from app.api import routes
from app.api.shopping import _use_user_tokens
from app.clients import ah_data as ahd
from app.clients.ah import ah_client
from app.database import get_db
from app.logging_config import logger
from app.models import Recipe

router = APIRouter(prefix="/api")

NOT_LINKED = "AH niet gekoppeld. Ga naar Instellingen."
STAPLES_CACHE = "ah_staples_cache"
STAPLES_WEEKS = 12
STAPLES_MAX_TRIPS = 20


def _fail(e: Exception | str) -> dict:
    return {"ok": False, "error": str(e) if isinstance(e, (ahd.AHDataError, str)) else "AH gaf geen antwoord."}


def _load(db: Session, key: str) -> dict | None:
    try:
        data = json.loads(routes._get_setting(db, key) or "null")
        return data if isinstance(data, dict) else None
    except ValueError:
        return None


def _save(db: Session, key: str, data: dict) -> None:
    routes._set_setting(db, key, json.dumps(data, ensure_ascii=False))


# ── 1. Bonus ───────────────────────────────────────────────────────────


def _period_dict(row) -> dict:
    return {"start": row.start, "end": row.end, "user": row.user, "fetched_at": row.fetched_at,
            "personal": row.personal, "groups": row.groups, "products": row.products}


async def bonus_for_week(db: Session, monday: date) -> dict:
    """Bonus voor de week waarvoor gepland wordt: deze periode, of die van volgende week zodra AH die toont.
    Valt terug op de huidige periode als de volgende nog niet bekend is."""
    today = date.today()
    current = ah_sync.bonus_period(db, today)
    if current and str(monday) > current.end:
        try:
            return await get_bonus(db, False, "next")
        except Exception as e:  # noqa: BLE001
            logger.info("Bonus van volgende week nog niet beschikbaar: %s", e)
    elif not current and monday > routes.monday_of(today):
        try:
            cur = await get_bonus(db, False, "current")
            if str(monday) <= cur["end"]:
                return cur
            return await get_bonus(db, False, "next")
        except Exception as e:  # noqa: BLE001
            logger.info("Bonus van volgende week nog niet beschikbaar: %s", e)
    return await get_bonus(db, False, "current")


async def get_bonus(db: Session, refresh: bool = False, period: str = "current") -> dict:
    """Bonus van deze ("current") of volgende ("next") periode uit `ah_bonus_periods`, anders vers bij AH.
    Vorm: {"start", "end", "user", "personal", "groups", "products": {webshopId: product}}."""
    user = _use_user_tokens(db)
    today = date.today()
    row = ah_sync.bonus_period(db, today) if period == "current" else None
    if period == "next":
        current = ah_sync.bonus_period(db, today)
        if current and current.end:
            row = ah_sync.bonus_period(db, date.fromisoformat(current.end) + timedelta(days=1))
    if row and not refresh and row.products and (row.user or not user):
        return _period_dict(row)
    fresh = await ahd.fetch_bonus(user, period)
    row = ah_sync.record_bonus(db, fresh, user)
    logger.info("AH bonus opgehaald: %d producten (%s t/m %s)", len(row.products), row.start, row.end)
    return _period_dict(row)


@router.get("/bonus")
async def api_bonus(refresh: bool = False, period: str = "current", db: Session = Depends(get_db)):
    """`period=next`: de bonus van volgende week, zodra AH die toont (handig vóór de besteldag)."""
    try:
        cache = await get_bonus(db, refresh, "next" if period == "next" else "current")
    except Exception as e:  # noqa: BLE001
        logger.warning("Bonus ophalen mislukt: %s", e)
        return _fail(e)
    products = sorted(cache["products"].values(), key=lambda p: -(p.get("saving") or 0))
    return {"ok": True, "period": {"start": cache.get("start", ""), "end": cache.get("end", "")},
            "count": len(products), "personal_count": cache.get("personal", 0),
            "products": [{k: p.get(k) for k in ("id", "title", "mechanism", "saving", "personal")}
                         for p in products[:40]]}


@router.get("/bonus/recipes")
async def api_bonus_recipes(limit: int = 30, refresh: bool = False, period: str = "current",
                            week: str | None = None, db: Session = Depends(get_db)):
    """Eigen recepten met ingrediënten in de bonus. `week=` kiest de bonusperiode van die week (volgende
    week zodra AH die toont); anders `period` (current | next)."""
    try:
        if week:
            cache = await bonus_for_week(db, routes.parse_week(week))
        else:
            cache = await get_bonus(db, refresh, "next" if period == "next" else "current")
    except Exception as e:  # noqa: BLE001
        logger.warning("Bonus ophalen mislukt: %s", e)
        return _fail(e)
    recipes = [{"id": r.id, "name": r.name, "image_url": r.image_url or "", "servings": r.servings or "",
                "total_time": r.total_time or "", "ah_recipe_id": r.ah_recipe_id, "ingredients": r.ingredients}
               for r in db.execute(select(Recipe)).scalars()]
    scored = ahd.score_recipes(recipes, cache["products"])
    return {"ok": True, "period": {"start": cache.get("start", ""), "end": cache.get("end", "")},
            "bonus_count": len(cache["products"]), "recipes": scored[:max(1, limit)]}


# ── 2. AH-lijsten (favorietenlijsten) ──────────────────────────────────


class ExtrasPayload(BaseModel):
    list_ids: list[str] = []
    products: list[dict] = []  # [{product_id, name, quantity}]


@router.get("/ah-lists")
async def api_ah_lists(db: Session = Depends(get_db)):
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    try:
        lists = await ahd.get_lists()
    except Exception as e:  # noqa: BLE001
        return _fail(e)
    return {"ok": True, "lists": [{**l, "is_basis": ahd.is_basis(l["name"])} for l in lists]}


@router.get("/ah-lists/{list_id}")
async def api_ah_list(list_id: str, db: Session = Depends(get_db)):
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    try:
        return {"ok": True, **await ahd.get_list_items(list_id)}
    except Exception as e:  # noqa: BLE001
        return _fail(e)


async def _put_on_list(list_ids: list[str], products: list[dict]) -> dict:
    groups, failed = [], []
    for lid in dict.fromkeys(list_ids):
        try:
            groups.append((await ahd.get_list_items(lid))["items"])
        except Exception as e:  # noqa: BLE001
            logger.warning("AH-lijst %s ophalen mislukt: %s", lid, e)
            failed.append(lid)
    items = ahd.merge_items(*groups, products)
    if not items:
        return {"ok": not failed, "added": 0, **({"error": "De AH-lijst kon niet worden opgehaald."} if failed else {})}
    try:
        await ah_client.add_to_cart(items)
    except Exception as e:  # noqa: BLE001
        logger.warning("Extra's op het AH-lijstje zetten mislukt: %s", str(e)[:200])
        return {"ok": False, "error": "Op het AH-lijstje zetten is mislukt."}
    return {"ok": True, "added": len(items), "lists_failed": failed}


@router.post("/ah-lists/{list_id}/to-list")
async def api_ah_list_to_list(list_id: str, db: Session = Depends(get_db)):
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    return await _put_on_list([list_id], [])


@router.post("/ah-extras/to-list")
async def api_extras_to_list(payload: ExtrasPayload, db: Session = Depends(get_db)):
    """AH-lijsten + losse producten (standaardboodschappen) in één keer op het lijstje, dubbelen samengevoegd."""
    if not payload.list_ids and not payload.products:
        return {"ok": True, "added": 0}
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    return await _put_on_list(payload.list_ids, payload.products)


# ── 3. Allerhande-favorieten ───────────────────────────────────────────


def _imported_ah_ids(db: Session) -> dict[int, int]:
    rows = db.execute(select(Recipe.ah_recipe_id, Recipe.id).where(Recipe.ah_recipe_id.is_not(None))).all()
    return {ah_id: rid for ah_id, rid in rows}


@router.get("/ah-favorite-recipes")
async def api_ah_favorite_recipes(db: Session = Depends(get_db)):
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    try:
        ids = await ahd.get_favorite_recipe_ids()
        titles = await ahd.recipe_titles(ids)
    except Exception as e:  # noqa: BLE001
        return _fail(e)
    have = _imported_ah_ids(db)
    recipes = [{"id": i, "title": titles.get(i, ""), "imported": i in have, "recipe_id": have.get(i)} for i in ids]
    return {"ok": True, "count": len(recipes), "new": sum(1 for r in recipes if not r["imported"]),
            "recipes": recipes}


@router.post("/ah-favorite-recipes/import")
async def api_ah_favorite_recipes_import(db: Session = Depends(get_db)):
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    try:
        ids = await ahd.get_favorite_recipe_ids()
    except Exception as e:  # noqa: BLE001
        return _fail(e)
    have = _imported_ah_ids(db)
    imported, failed, errors = 0, 0, []
    for rid in ids:
        if rid in have:
            continue
        result = await routes.import_allerhande_recipe(db, rid)
        if result["ok"] and result.get("new"):
            imported += 1
            have[rid] = result["id"]
        elif not result["ok"]:
            failed += 1
            errors.append(f"{rid}: {result['error'][:120]}")
    logger.info("AH-favorieten: %d gevonden, %d geïmporteerd, %d mislukt", len(ids), imported, failed)
    return {"ok": True, "total": len(ids), "imported": imported, "skipped": len(ids) - imported - failed,
            "failed": failed, "errors": errors[:10]}


# ── 4. Standaardboodschappen ───────────────────────────────────────────


async def _history(db: Session, refresh: bool) -> dict:
    cache = _load(db, STAPLES_CACHE)
    if not refresh and cache and ahd.is_fresh(cache.get("fetched_at", ""), 24):
        return cache
    since = date.today() - timedelta(weeks=STAPLES_WEEKS)
    trips, counts, errors = [], {"kassabonnen": 0, "bestellingen": 0}, 0
    for key, fetch in (("kassabonnen", ahd.receipt_trips), ("bestellingen", ahd.order_trips)):
        try:
            got = await fetch(since, STAPLES_MAX_TRIPS)
        except Exception as e:  # noqa: BLE001
            logger.warning("Standaardboodschappen: %s mislukt: %s", key, e)
            errors += 1
            continue
        counts[key] = len(got)
        trips.extend(got)
    if errors == 2:
        raise ahd.AHDataError("Je kassabonnen en bestellingen konden niet worden opgehaald.")
    trips.sort(key=lambda t: t.get("date", ""), reverse=True)
    trips = [{**t, "products": {str(k): v for k, v in t["products"].items()}} for t in trips[:STAPLES_MAX_TRIPS]]
    cache = {"fetched_at": ahd.now_iso(), "trips": trips, "counts": counts}
    _save(db, STAPLES_CACHE, cache)
    return cache


async def _basislijst() -> list[dict]:
    try:
        basis = [l for l in await ahd.get_lists() if ahd.is_basis(l["name"])]
        return (await ahd.get_list_items(basis[0]["id"]))["items"] if basis else []
    except ahd.AHDataError as e:
        logger.warning("Basislijst ophalen mislukt: %s", e)
        return []


@router.get("/staples")
async def api_staples(week: str | None = None, refresh: bool = False, db: Session = Depends(get_db)):
    monday = routes.parse_week(week)
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    try:
        history = await _history(db, refresh)
    except Exception as e:  # noqa: BLE001
        return _fail(e)
    basis = await _basislijst()
    cart, _ = routes.week_cart(db, monday)
    exclude = {int(c["product_id"]) for c in cart if c.get("product_id")}
    staples = ahd.compute_staples(history["trips"], exclude, basis, max_trips=STAPLES_MAX_TRIPS)
    for s in staples:
        s["source"] = "vaak"
    # "Waarschijnlijk op" uit het koopritme (ah_trips) erbij, vóór de rest: dat is het meest urgent.
    due = [r for r in replenish_due(db, monday) if r["product_id"] not in exclude]
    have = {s["product_id"] for s in staples}
    merged = [{"product_id": r["product_id"], "name": r["name"], "times": r["times"], "in_basislijst": False,
               "last_bought": r["last_bought"], "source": "ritme", "status": r["status"], "due_on": r["due_on"],
               "interval_days": r["interval_days"]} for r in due if r["product_id"] not in have]
    for s in staples:
        hit = next((r for r in due if r["product_id"] == s["product_id"]), None)
        if hit:
            s.update(source="ritme", status=hit["status"], due_on=hit["due_on"], interval_days=hit["interval_days"])
    staples = merged + staples
    staples.sort(key=lambda s: (s.get("source") != "ritme", s.get("status") != "op"))  # stabiel: ritme eerst
    counts = history.get("counts") or {}
    return {"ok": True, "week": str(monday), "staples": staples,
            "source_counts": {**counts, "ritten": len(history["trips"]), "basislijst": len(basis),
                              "waarschijnlijk_op": len(due)}}


def replenish_due(db: Session, monday: date) -> list[dict]:
    from app import replenish

    trips = ah_sync.trips_as_dicts(ah_sync.trips_since(db, date.today() - timedelta(weeks=52)))
    rows = replenish.predict(trips, snooze=replenish.load_snooze(db))
    return [r for r in rows if r["status"] in ("op", "binnenkort")]


# ── 5. AH-datalaag (sync) ──────────────────────────────────────────────


@router.post("/ah/sync")
async def api_ah_sync(db: Session = Depends(get_db)):
    """Nieuwe bestellingen en kassabonnen ophalen naar `ah_trips` (alleen wat we nog niet hebben)."""
    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    try:
        result = await ah_sync.sync_trips(db)
    except Exception as e:  # noqa: BLE001
        logger.warning("AH-sync mislukt: %s", e)
        return _fail(e)
    return {"ok": True, **result, "status": ah_sync.sync_status(db)}


@router.get("/ah/sync/status")
async def api_ah_sync_status(db: Session = Depends(get_db)):
    return {"ok": True, "linked": _use_user_tokens(db), **ah_sync.sync_status(db)}



@router.post("/packs/sync")
async def packs_sync():
    """AH-maaltijdpakketten (verspakketten) ophalen/bijwerken als recepten, op de achtergrond."""
    import asyncio

    from app import packs
    from app.database import SessionLocal

    async def run():
        with SessionLocal() as db:
            await packs.sync(db)

    if not packs.STATUS["running"]:
        packs.STATUS["running"] = True
        asyncio.create_task(run())
    return {"ok": True, "status": packs.STATUS}


@router.get("/packs/status")
async def packs_status(db: Session = Depends(get_db)):
    from app import packs

    return {"ok": True, "status": packs.STATUS, "synced_on": routes._get_setting(db, "packs_synced_on"),
            "count": db.query(Recipe).filter(Recipe.collection == packs.COLLECTION, Recipe.archived.is_(False)).count()}
