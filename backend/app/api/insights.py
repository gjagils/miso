"""Inzichten uit de AH-datalaag: kosten van recept en week, uitgaven per week, waarschijnlijk op.

Alles hier leest uit onze eigen tabellen (`ah_trips`, `ah_prices`, `ah_bonus_periods`); er wordt
niets bij AH opgehaald. Vullen gebeurt via `POST /api/ah/sync` en de prijssnapshots bij het koppelen.
"""

from datetime import date, timedelta

from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import ah_sync, cookwith, costs, planning, replenish
from app.api import routes
from app.database import get_db
from app.models import Recipe

router = APIRouter(prefix="/api")

HISTORY_WEEKS = 52


@router.get("/cook-with")
async def api_cook_with(db: Session = Depends(get_db)):
    """Koken met wat er is: eigen recepten die passen bij de vriezer en de laatst gekochte producten."""
    return {"ok": True, **cookwith.suggest(db)}


@router.get("/week/cost")
async def api_week_cost(week: str | None = None, db: Session = Depends(get_db)):
    """Geschatte kosten van het weekmenu (gekoppelde producten x verpakkingen, met bonus)."""
    return {"ok": True, **costs.week_cost(db, routes.parse_week(week))}


@router.get("/recipes/{recipe_id}/cost")
async def api_recipe_cost(recipe_id: int, persons: int | None = Query(None, ge=1, le=planning.MAX_PERSONS),
                          db: Session = Depends(get_db)):
    recipe = db.get(Recipe, recipe_id)
    if not recipe:
        return JSONResponse({"ok": False, "error": "Recept niet gevonden."}, status_code=404)
    return {"ok": True, "recipe_id": recipe.id, **costs.recipe_cost(db, recipe, persons)}


def week_detail(trips: list, monday: date) -> dict:
    """Waar ging het geld heen in één week: grootste regels en bedrag per categorie."""
    end = monday + timedelta(days=6)
    mine = [t for t in trips if str(monday) <= t.date <= str(end)]
    lines: dict[int | str, dict] = {}
    cats: dict[str, float] = {}
    for t in mine:
        for ln in t.lines:
            amount = ln.get("amount")
            if amount is None:
                continue
            key = ln.get("product_id") or ln.get("name", "")
            row = lines.setdefault(key, {"product_id": ln.get("product_id") or 0, "name": ln.get("name", ""),
                                         "quantity": 0.0, "amount": 0.0, "bonus": False})
            row["quantity"] += float(ln.get("quantity") or 1)
            row["amount"] = round(row["amount"] + amount, 2)
            row["bonus"] = row["bonus"] or bool(ln.get("bonus"))
            cat = ln.get("category") or "Overig"
            cats[cat] = round(cats.get(cat, 0.0) + amount, 2)
    top = sorted(lines.values(), key=lambda r: -r["amount"])[:10]
    categories = sorted(({"category": c, "amount": a} for c, a in cats.items()), key=lambda r: -r["amount"])
    return {"week": str(monday), "trips": [{"id": t.id, "source": t.source, "date": t.date, "total": t.total,
                                            "discount": t.discount, "lines": len(t.lines)} for t in mine],
            "top": top, "categories": categories}


@router.get("/spend")
async def api_spend(weeks: int = Query(12, ge=1, le=104), detail: str | None = None, db: Session = Depends(get_db)):
    """Uitgaven per week uit bestellingen en kassabonnen. `detail=YYYY-MM-DD` geeft van die week de
    grootste regels en de bedragen per categorie."""
    today = date.today()
    monday = routes.monday_of(today)
    first = monday - timedelta(weeks=weeks - 1)
    trips = ah_sync.trips_since(db, first)
    per_week: dict[str, dict] = {str(first + timedelta(weeks=i)): {"week": str(first + timedelta(weeks=i)), "total": 0.0,
                                                                   "discount": 0.0, "trips": 0, "unknown": 0}
                                 for i in range(weeks)}
    for t in trips:
        key = str(routes.monday_of(date.fromisoformat(t.date)))
        w = per_week.get(key)
        if not w:
            continue
        w["trips"] += 1
        if t.total is None:
            w["unknown"] += 1
        else:
            w["total"] = round(w["total"] + t.total, 2)
        w["discount"] = round(w["discount"] + (t.discount or 0), 2)
    rows = list(per_week.values())
    known = [w["total"] for w in rows if w["trips"] and not w["unknown"]]
    household = planning.household_size(db)
    avg = round(sum(known) / len(known), 2) if known else None
    out = {"ok": True, "weeks": rows, "average_week": avg, "household_size": household,
           "average_per_person_day": round(avg / household / 7, 2) if avg else None,
           "trips_total": len(trips), "since": str(first)}
    if detail:
        out["detail"] = week_detail(trips, routes.parse_week(detail))
    return out


@router.get("/replenish")
async def api_replenish(week: str | None = None, db: Session = Depends(get_db)):
    """Waarschijnlijk op: producten die volgens het koopritme aan de beurt zijn, minus wat het weekmenu
    al meeneemt. Leeg zolang er geen (gesynchroniseerde) bestellingen zijn."""
    monday = routes.parse_week(week)
    trips = ah_sync.trips_as_dicts(ah_sync.trips_since(db, date.today() - timedelta(weeks=HISTORY_WEEKS)))
    cart, _ = routes.week_cart(db, monday)
    exclude = {int(c["product_id"]) for c in cart if c.get("product_id")}
    pantry = replenish.pantry_terms(db.execute(select(Recipe)).scalars().all())
    rows = replenish.predict(trips, snooze=replenish.load_snooze(db), exclude=exclude, pantry=pantry)
    due = [r for r in rows if r["status"] in ("op", "binnenkort")]
    return {"ok": True, "week": str(monday), "trips": len(trips), "due": due,
            "due_count": len(due), "tracked": len(rows), "later": [r for r in rows if r["status"] == "ok"][:20]}


class SnoozePayload(BaseModel):
    product_id: int
    days: int = Field(14, ge=1, le=365)


@router.post("/replenish/snooze")
async def api_replenish_snooze(payload: SnoozePayload, db: Session = Depends(get_db)):
    """"Hebben we nog": dit product pas weer tonen na `days` dagen."""
    until = replenish.snooze(db, payload.product_id, payload.days)
    return {"ok": True, "product_id": payload.product_id, "snoozed_until": until}


class OutPayload(BaseModel):
    product_id: int
    name: str = Field("", max_length=200)
    quantity: int = Field(1, ge=1, le=20)


@router.post("/replenish/out")
async def api_replenish_out(payload: OutPayload, db: Session = Depends(get_db)):
    """"Dit is op" (bijv. tijdens het koken): op het AH-lijstje en de voorspelling even met rust laten.
    Alleen ouders (zie `family.KID_BLOCKED`). Bestelt niets."""
    from app.api.ah_data import NOT_LINKED, _fail, _put_on_list
    from app.api.shopping import _use_user_tokens

    if not _use_user_tokens(db):
        return _fail(NOT_LINKED)
    result = await _put_on_list([], [{"product_id": payload.product_id, "name": payload.name,
                                      "quantity": payload.quantity}])
    if result.get("ok"):
        trips = ah_sync.trips_as_dicts(ah_sync.trips_since(db, date.today() - timedelta(weeks=HISTORY_WEEKS)))
        known = next((r for r in replenish.predict(trips) if r["product_id"] == payload.product_id), None)
        replenish.snooze(db, payload.product_id, max(7, (known or {}).get("interval_days") or 14))
    return result


@router.post("/recipes/{recipe_id}/cheaper")
async def api_recipe_cheaper(recipe_id: int, db: Session = Depends(get_db)):
    """Goedkopere AH-producten voor dit recept (zoekt bij AH, dus met een POST: niet vooraf ophalen).
    Wijzigt niets; kiezen gaat via `POST /api/recipes/{id}/ingredients/{index}`."""
    from app import cheaper

    recipe = db.get(Recipe, recipe_id)
    if not recipe:
        return JSONResponse({"ok": False, "error": "Recept niet gevonden."}, status_code=404)
    found = await cheaper.cheaper_for(recipe, routes.search_candidates)
    if found["unreachable"]:  # AH gaf nergens antwoord: niet doen alsof er niets goedkopers is
        return {"ok": False, "unreachable": True, "recipe_id": recipe.id, "suggestions": [], "total_saving": 0,
                "error": "AH gaf geen antwoord. Probeer het later nog eens."}
    suggestions = found["suggestions"]
    return {"ok": True, "unreachable": False, "recipe_id": recipe.id, "suggestions": suggestions,
            "total_saving": round(sum(x["saving"] for x in suggestions), 2)}
