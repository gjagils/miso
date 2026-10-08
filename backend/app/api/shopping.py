"""Dekking van de koppeling, AH-mandje (vullen/leegmaken, nooit bestellen) en de add-multiple-link."""

import asyncio
from datetime import datetime

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api import routes
from app.clients.ah import ah_client, build_add_multiple_url, get_active_order, set_order_items
from app.database import SessionLocal, get_db
from app.logging_config import logger
from app.matching import MATCH_VERSION
from app.models import BasketPush, ProductPreference, Recipe

router = APIRouter()


# ── Dekking ────────────────────────────────────────────────────────────


def recipe_coverage(recipe: Recipe) -> dict:
    ings = recipe.ingredients
    stats = {"totaal": len(ings), "gekoppeld": 0, "basis": 0, "uitgevinkt": 0, "open": 0,
             "handmatig": 0, "geleerd": 0, "verouderd": 0}
    open_items = []
    for i in ings:
        if i.get("auto_skip"):
            stats["basis"] += 1
        elif i.get("skip"):
            stats["uitgevinkt"] += 1
        elif (i.get("product") or {}).get("id"):
            stats["gekoppeld"] += 1
            if i.get("manual"):
                stats["handmatig"] += 1
            elif i.get("source") == "geleerd":
                stats["geleerd"] += 1
        else:
            stats["open"] += 1
            open_items.append(i.get("text", ""))
        if not i.get("manual") and i.get("match_v") != MATCH_VERSION:
            stats["verouderd"] += 1
    nodig = stats["totaal"] - stats["basis"] - stats["uitgevinkt"]
    stats["pct"] = round(100 * stats["gekoppeld"] / nodig, 1) if nodig else 100.0
    return {"id": recipe.id, "name": recipe.name, **stats, "open_items": open_items}


def coverage(db: Session) -> dict:
    rows = [recipe_coverage(r) for r in db.execute(select(Recipe).order_by(Recipe.name)).scalars()]
    tot = {k: sum(r[k] for r in rows) for k in ("totaal", "gekoppeld", "basis", "uitgevinkt", "open", "handmatig",
                                                 "geleerd", "verouderd")}
    nodig = tot["totaal"] - tot["basis"] - tot["uitgevinkt"]
    tot["pct"] = round(100 * tot["gekoppeld"] / nodig, 1) if nodig else 100.0
    tot["recepten"] = len(rows)
    tot["volledig"] = sum(1 for r in rows if r["open"] == 0)
    tot["geleerde_voorkeuren"] = db.query(ProductPreference).count()
    rows.sort(key=lambda r: (r["pct"], -r["open"], r["name"]))
    return {"totaal": tot, "recepten": rows, "refresh": REFRESH}


REFRESH: dict = {"running": False, "done": 0, "total": 0, "started": None, "finished": None, "error": None}


async def _refresh_all(force: bool) -> None:
    REFRESH.update(running=True, done=0, error=None, started=datetime.now().isoformat(timespec="seconds"),
                   finished=None)
    try:
        with SessionLocal() as db:
            ids = [r.id for r in db.execute(select(Recipe)).scalars()]
            REFRESH["total"] = len(ids)
            prefs = routes.load_prefs(db)
            for rid in ids:
                recipe = db.get(Recipe, rid)
                ings = recipe.ingredients
                try:
                    await routes._automatch(ings, recipe.gf_mode != "none", force=force, prefs=prefs)
                    recipe.ingredients = ings
                    db.commit()
                except Exception as e:  # noqa: BLE001
                    logger.warning("Coverage refresh failed for recipe %s: %s", rid, e)
                REFRESH["done"] += 1
    except Exception as e:  # noqa: BLE001
        REFRESH["error"] = str(e)
    finally:
        REFRESH.update(running=False, finished=datetime.now().isoformat(timespec="seconds"))


@router.get("/api/coverage")
async def api_coverage(db: Session = Depends(get_db)):
    return coverage(db)


@router.post("/api/coverage/refresh")
async def api_coverage_refresh(force: bool = False):
    if not REFRESH["running"]:
        asyncio.create_task(_refresh_all(force))
    return {"ok": True, "refresh": REFRESH}


@router.get("/dekking", response_class=HTMLResponse)
async def coverage_page(request: Request, db: Session = Depends(get_db)):
    return routes.templates.TemplateResponse(request, "coverage.html", coverage(db))


# ── Mandje (actieve bestelling) en lijst-link ──────────────────────────


class BasketPayload(BaseModel):
    week: str | None = None
    recipe_ids: list[int] = []


def _cart_for(db: Session, payload: BasketPayload) -> list[dict]:
    if payload.recipe_ids:
        recipes = [r for r in (db.get(Recipe, i) for i in dict.fromkeys(payload.recipe_ids)) if r]
    else:
        recipes = routes._week_recipes(db, routes.parse_week(payload.week))
    cart, _ = routes.aggregate_cart(recipes)
    return cart


def _use_user_tokens(db: Session) -> bool:
    access, refresh = routes._get_setting(db, "ah_user_token"), routes._get_setting(db, "ah_refresh_token")
    if not access and not refresh:
        return False

    def save(a: str, r: str) -> None:
        routes._set_setting(db, "ah_user_token", a)
        routes._set_setting(db, "ah_refresh_token", r)

    ah_client.set_user_tokens(access, refresh, on_tokens_updated=save)
    return True


def _summarize_order(order: dict) -> dict:
    items = []
    for it in order.get("items") or order.get("orderedProducts") or []:
        prod = it.get("product") or {}
        items.append({"product_id": it.get("productId") or prod.get("webshopId"),
                      "name": prod.get("title") or it.get("description", ""), "quantity": it.get("quantity", 0)})
    return {"items": items, "count": len(items),
            "total": (order.get("orderSummary") or order).get("totalPrice") if isinstance(order, dict) else None}


@router.get("/api/basket")
async def api_basket(db: Session = Depends(get_db)):
    if not _use_user_tokens(db):
        return {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}
    try:
        return {"ok": True, **_summarize_order(await get_active_order(ah_client))}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": str(e)}


@router.post("/api/basket/fill")
async def api_basket_fill(payload: BasketPayload, db: Session = Depends(get_db)):
    """Zet de producten van een week (of recepten) in het AH-mandje. Bestelt niets."""
    cart = _cart_for(db, payload)
    if not cart:
        return {"ok": False, "error": "Geen gekoppelde producten om in het mandje te zetten."}
    if not _use_user_tokens(db):
        return {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}
    try:
        current = {i["product_id"]: i["quantity"] for i in _summarize_order(await get_active_order(ah_client))["items"]}
        items = [{"product_id": c["product_id"], "quantity": current.get(c["product_id"], 0) + c["quantity"]}
                 for c in cart]
        await set_order_items(ah_client, items)
    except Exception as e:  # noqa: BLE001
        logger.error("Basket fill failed: %s", e)
        return {"ok": False, "error": str(e)}
    rows = {r.product_id: r for r in db.execute(select(BasketPush)).scalars()}
    for c in cart:
        row = rows.get(c["product_id"])
        if row:
            row.quantity += c["quantity"]
        else:
            db.add(BasketPush(product_id=c["product_id"], quantity=c["quantity"], name=c.get("name", "")))
    db.commit()
    return {"ok": True, "added": len(cart)}


@router.post("/api/basket/clear")
async def api_basket_clear(db: Session = Depends(get_db)):
    """Haalt weg wat Miso in het mandje zette (de rest van het mandje blijft staan). Bestelt niets."""
    pushes = list(db.execute(select(BasketPush)).scalars())
    if not pushes:
        return {"ok": True, "removed": 0}
    if not _use_user_tokens(db):
        return {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}
    try:
        current = {i["product_id"]: i["quantity"] for i in _summarize_order(await get_active_order(ah_client))["items"]}
        items = [{"product_id": p.product_id, "quantity": max(0, current.get(p.product_id, 0) - p.quantity)}
                 for p in pushes]
        await set_order_items(ah_client, items)
    except Exception as e:  # noqa: BLE001
        logger.error("Basket clear failed: %s", e)
        return {"ok": False, "error": str(e)}
    for p in pushes:
        db.delete(p)
    db.commit()
    return {"ok": True, "removed": len(pushes)}


@router.post("/api/list-link")
async def api_list_link(payload: BasketPayload, db: Session = Depends(get_db)):
    """Link naar ah.nl die de producten via je eigen AH-sessie op 'Mijn lijst' zet (geen token nodig)."""
    cart = _cart_for(db, payload)
    return {"ok": bool(cart), "url": build_add_multiple_url(cart) if cart else "", "count": len(cart)}
