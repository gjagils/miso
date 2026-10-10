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
from app.matching import MATCH_VERSION, needed, pack_size, packs_for, query_terms
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


def missing_groups(db: Session, week: str | None = None) -> list[dict]:
    """Open ingrediënten over alle recepten (of alleen de recepten van één week), gegroepeerd op zoekterm."""
    from app import planning

    groups: dict[str, dict] = {}
    if week:
        ids = {r.id for r in planning.week_grocery_input(db, routes.parse_week(week))[0]}
        recipes = [r for r in db.execute(select(Recipe).where(Recipe.id.in_(ids)).order_by(Recipe.name)).scalars()]
    else:
        recipes = db.execute(select(Recipe).where(Recipe.archived.is_(False)).order_by(Recipe.name)).scalars().all()
    for recipe in recipes:
        for idx, ing in enumerate(recipe.ingredients):
            if ing.get("skip") or ing.get("auto_skip") or (ing.get("product") or {}).get("id"):
                continue
            text = (ing.get("text") or "").strip()
            term = query_terms(ing.get("search") or text)[0] or text.lower()
            g = groups.setdefault(term, {"term": term, "lines": []})
            g["lines"].append({"recipe_id": recipe.id, "recipe": recipe.name, "index": idx, "text": text})
    return sorted(groups.values(), key=lambda g: (-len(g["lines"]), g["term"]))


class AssignPayload(BaseModel):
    lines: list[dict]  # [{recipe_id, index, text}]
    product: dict | None = None  # None = niet nodig (uitvinken)


@router.post("/api/missing/assign")
async def assign_missing(payload: AssignPayload, db: Session = Depends(get_db)):
    """Kies één product voor dezelfde ontbrekende regel in alle recepten (handmatig + onthouden), of vink uit."""
    done, learned = 0, False
    for line in payload.lines:
        recipe = db.get(Recipe, int(line.get("recipe_id", 0)))
        if not recipe:
            continue
        ings = recipe.ingredients
        idx = int(line.get("index", -1))
        if not (0 <= idx < len(ings)) or ings[idx].get("text", "").strip() != str(line.get("text", "")).strip():
            continue  # recept is intussen gewijzigd: niet de verkeerde regel aanpassen
        ing = ings[idx]
        if payload.product:
            ing.update(product=payload.product, manual=True, source="handmatig", skip=False, auto_skip=False,
                       match_v=MATCH_VERSION)
            need, pack = needed(ing.get("text", "")), pack_size(payload.product.get("unit_size", ""))
            ing["quantity"] = packs_for(need, pack) or 1
            if not learned:
                routes.learn_pref(db, ing)
                learned = True
        else:
            ing.update(skip=True, auto_skip=False, product=None)
        recipe.ingredients = ings
        done += 1
    db.commit()
    return {"ok": True, "updated": done, "totaal": coverage(db)["totaal"]}


@router.get("/dekking/ontbrekend", response_class=HTMLResponse)
async def missing_page(request: Request, week: str | None = None, db: Session = Depends(get_db)):
    groups = missing_groups(db, week)
    return routes.templates.TemplateResponse(request, "missing.html", {
        "groups": groups, "lines": sum(len(g["lines"]) for g in groups), "totaal": coverage(db)["totaal"],
        "week": week, "week_label": routes.day_label(routes.parse_week(week)) if week else ""})


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
    persons: dict[str, int] = {}  # recipe id -> personen voor losse recepten (leeg = huishoudgrootte)


def _cart_for(db: Session, payload: BasketPayload) -> list[dict]:
    if payload.recipe_ids:
        recipes = [r for r in (db.get(Recipe, i) for i in dict.fromkeys(payload.recipe_ids)) if r]
        cart, _ = routes.aggregate_cart(recipes, routes.recipe_factors(db, recipes, payload.persons))
    else:
        cart, _ = routes.week_cart(db, routes.parse_week(payload.week))
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
    for it in order.get("orderedProducts") or order.get("items") or []:
        prod = it.get("product") or {}
        items.append({"product_id": it.get("productId") or prod.get("webshopId"),
                      "name": prod.get("title") or it.get("description", ""), "quantity": it.get("quantity", 0)})
    total = order.get("totalPrice") or {}
    return {"order_id": order.get("id"), "state": order.get("state"), "items": items, "count": len(items),
            "total": total.get("priceTotalPayable") if isinstance(total, dict) else total,
            "delivery": (order.get("deliveryInformation") or {}).get("deliveryDate")}


def _order_id(order: dict) -> str | None:
    oid = order.get("id") or order.get("orderId")
    return str(oid) if oid else None


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
        order = await get_active_order(ah_client)
        order_id = _order_id(order)
        current = {i["product_id"]: i["quantity"] for i in _summarize_order(order)["items"]}
        items = [{"product_id": c["product_id"], "quantity": current.get(c["product_id"], 0) + c["quantity"]}
                 for c in cart]
        await set_order_items(ah_client, items)
    except Exception as e:  # noqa: BLE001
        logger.error("Basket fill failed: %s", e)
        return {"ok": False, "error": str(e)}
    for old in db.execute(select(BasketPush).where(BasketPush.order_id != order_id)).scalars():
        db.delete(old)  # hoorde bij een eerdere (geplaatste) bestelling: niet meer van ons
    rows = {r.product_id: r for r in db.execute(select(BasketPush).where(BasketPush.order_id == order_id)).scalars()}
    for c in cart:
        row = rows.get(c["product_id"])
        if row:
            row.quantity += c["quantity"]
        else:
            db.add(BasketPush(product_id=c["product_id"], quantity=c["quantity"], name=c.get("name", ""),
                              order_id=order_id))
    db.commit()
    return {"ok": True, "added": len(cart)}


@router.post("/api/basket/clear")
async def api_basket_clear(db: Session = Depends(get_db)):
    """Haalt weg wat Miso in het mandje zette (de rest van het mandje blijft staan). Bestelt niets."""
    all_pushes = list(db.execute(select(BasketPush)).scalars())
    if not all_pushes:
        return {"ok": True, "removed": 0}
    if not _use_user_tokens(db):
        return {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}
    try:
        order = await get_active_order(ah_client)
        order_id = _order_id(order)
        # alleen wat Miso in dít mandje zette; oude regels (eerdere bestelling) laten we met rust
        pushes = [p for p in all_pushes if p.order_id in (order_id, None)]
        current = {i["product_id"]: i["quantity"] for i in _summarize_order(order)["items"]}
        items = [{"product_id": p.product_id, "quantity": max(0, current.get(p.product_id, 0) - p.quantity)}
                 for p in pushes]
        if items:
            await set_order_items(ah_client, items)
    except Exception as e:  # noqa: BLE001
        logger.error("Basket clear failed: %s", e)
        return {"ok": False, "error": str(e)}
    for p in all_pushes:
        db.delete(p)
    db.commit()
    return {"ok": True, "removed": len(pushes)}


@router.post("/api/list-link")
async def api_list_link(payload: BasketPayload, db: Session = Depends(get_db)):
    """Link naar ah.nl die de producten via je eigen AH-sessie op 'Mijn lijst' zet (geen token nodig)."""
    cart = _cart_for(db, payload)
    return {"ok": bool(cart), "url": build_add_multiple_url(cart) if cart else "", "count": len(cart)}


# ── Staan de boodschappen van een gerecht al klaar? ────────────────────
# "Klaar" = op het AH-lijstje of al in de lopende bestelling. Extra dingen op het lijstje maken niet uit;
# mist de helft of meer van de producten van een gerecht, dan moet het nog op het lijstje.

MISSING_LIMIT = 0.5  # mist de helft of meer van een gerecht: nog op het lijstje zetten


def invalidate_presence() -> None:
    """Oude naam: na een actie wordt nu actief opnieuw gecontroleerd (zie check_list)."""


async def check_list(db: Session) -> dict | None:
    """Lees één keer het AH-lijstje + de lopende bestelling en bewaar wat er klaarstaat. Alleen na een actie of
    op de knop 'Controleer met AH', niet bij elke paginaweergave."""
    import json
    from datetime import datetime

    from app.clients.ah import get_shopping_list

    if not _use_user_tokens(db):
        return None
    ids: set[int] = set()
    try:
        ids |= set((await get_shopping_list(ah_client)).keys())
    except Exception as e:  # noqa: BLE001
        logger.warning("AH-lijstje controleren mislukt: %s", e)
        return None
    try:
        ids |= {int(i["product_id"]) for i in _summarize_order(await get_active_order(ah_client))["items"]
                if i.get("product_id")}
    except Exception:  # noqa: BLE001 - geen lopende bestelling
        pass
    snap = {"checked_at": datetime.now().isoformat(timespec="minutes"), "ids": sorted(ids)}
    routes._set_setting(db, "list_check", json.dumps(snap))
    return snap


def last_check(db: Session) -> dict | None:
    import json

    raw = routes._get_setting(db, "list_check")
    try:
        return json.loads(raw) if raw else None
    except ValueError:
        return None


def entry_list_status(db: Session, monday, present: set[int]) -> list[dict]:
    from app import planning

    household = planning.household_size(db)
    out = []
    for e in planning.week_entries(db, monday):
        if e.kind != "recipe":
            continue
        recipe = db.get(Recipe, e.recipe_id)
        if not recipe:
            continue
        factor = planning.scale_factor(planning.grocery_persons(e, household), recipe)
        cart, _ = routes.aggregate_cart([recipe], [factor])
        ids = {c["product_id"] for c in cart}
        missing = [c["name"] for c in cart if c["product_id"] not in present]
        total = len(ids)
        todo = bool(total) and len(missing) / total >= MISSING_LIMIT
        out.append({"entry_id": e.id, "date": e.date, "recipe_id": recipe.id, "name": routes._short_name(recipe.name),
                    "total": total, "present": total - len(missing), "missing": missing[:8],
                    "status": "todo" if todo else "ok"})
    return out


@router.get("/api/plan/list-status")
async def api_list_status(week: str | None = None, check: bool = False, db: Session = Depends(get_db)):
    """Per gepland gerecht: staan de boodschappen al op het AH-lijstje (of in de bestelling)?

    Alleen voor weken die nog besteld moeten worden: de bestelling (bijv. zondag) is voor de week van maandag t/m
    zondag erna. De lopende week is al besteld en geleverd, daar zegt het lijstje niets meer over."""
    from datetime import date

    monday = routes.parse_week(week)
    if monday <= date.today():
        return {"ok": True, "connected": True, "week": str(monday), "entries": [], "todo_count": 0,
                "already_ordered": True}
    connected = bool(routes._get_setting(db, "ah_user_token") or routes._get_setting(db, "ah_refresh_token"))
    snap = await check_list(db) if (check and connected) else last_check(db)
    if not connected or not snap:
        return {"ok": True, "connected": connected, "week": str(monday), "entries": [], "todo_count": 0,
                "checked_at": None}
    entries = entry_list_status(db, monday, set(snap["ids"]))
    return {"ok": True, "connected": True, "week": str(monday), "entries": entries, "checked_at": snap["checked_at"],
            "todo_count": sum(1 for e in entries if e["status"] == "todo")}
