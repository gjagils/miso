"""Wat kost het? Geschatte kosten van een recept en van een week, uit de gekoppelde AH-producten.

Prijs per product: de prijs die bij het koppelen is bewaard, anders het laatste prijssnapshot (`ah_prices`).
Staat het product in de bonus van de periode, dan rekenen we met de bonusprijs en tellen de besparing.
Schatting: verpakkingen x prijs; wat overblijft van een pak telt gewoon mee (dat koop je immers).
"""

from datetime import date, timedelta

from sqlalchemy.orm import Session

from app import ah_sync, planning
from app.models import AHBonusPeriod, Recipe


def _num(v) -> float | None:
    return ah_sync._num(v)


def price_table(db: Session, products: list[dict], bonus: AHBonusPeriod | None) -> dict[int, dict]:
    """Per product-id: {"price", "bonus_price", "mechanism"} (None als onbekend)."""
    ids = [int(p["id"]) for p in products if p and p.get("id")]
    snapshots = ah_sync.latest_prices(db, ids)
    offers = bonus.products if bonus else {}
    out: dict[int, dict] = {}
    for p in products:
        pid = int(p.get("id") or 0)
        if not pid or pid in out:
            continue
        price = _num(p.get("price"))
        snap = snapshots.get(pid)
        if price is None and snap:
            price = snap.price
        offer = offers.get(pid)
        bonus_price = None
        if offer:
            bonus_price = _num(offer.get("now"))
            if bonus_price is None and offer.get("saving") is not None and price is not None:
                bonus_price = round(max(0.0, price - float(offer["saving"])), 2)
        out[pid] = {"price": price, "bonus_price": bonus_price, "mechanism": (offer or {}).get("mechanism", "")}
    return out


def price_cart(db: Session, cart: list[dict], products: list[dict], bonus: AHBonusPeriod | None) -> dict:
    """cart: [{"product_id", "quantity", "name"}] (uit aggregate_cart). Geeft totalen en regels."""
    table = price_table(db, products, bonus)
    lines, total, saving, unknown = [], 0.0, 0.0, []
    for item in cart:
        pid = int(item.get("product_id") or 0)
        qty = max(1, int(item.get("quantity") or 1))
        info = table.get(pid) or {}
        price, bonus_price = info.get("price"), info.get("bonus_price")
        if price is None and bonus_price is None:
            unknown.append(item.get("name", ""))
            lines.append({**item, "price": None, "amount": None, "bonus": False})
            continue
        pay = bonus_price if bonus_price is not None else price
        amount = round(pay * qty, 2)
        total += amount
        if bonus_price is not None and price is not None and price > bonus_price:
            saving += round((price - bonus_price) * qty, 2)
        lines.append({**item, "price": pay, "amount": amount, "bonus": bonus_price is not None,
                      "mechanism": info.get("mechanism", "")})
    return {"total": round(total, 2), "bonus_saving": round(saving, 2), "unknown": unknown,
            "known_count": len(cart) - len(unknown), "lines": lines}


def _products_of(recipes: list[Recipe], extras: list[dict] | None = None) -> list[dict]:
    out = [p for r in recipes for i in r.ingredients for p in (i.get("product"), i.get("gf_product")) if p and p.get("id")]
    out += [x["product"] for x in extras or [] if (x.get("product") or {}).get("id")]
    return out


def recipe_cost(db: Session, recipe: Recipe, persons: int | None = None, bonus: AHBonusPeriod | None = None,
                when: date | None = None) -> dict:
    """Geschatte kosten van één recept voor `persons` (default huishoudgrootte), ook per persoon."""
    from app.api.routes import aggregate_cart  # hier importeren: routes importeert planning/costs

    persons = persons or planning.household_size(db)
    bonus = bonus if bonus is not None else ah_sync.bonus_period(db, when)
    cart, unmatched = aggregate_cart([recipe], [planning.scale_factor(persons, recipe)])
    priced = price_cart(db, cart, _products_of([recipe]), bonus)
    per_person = round(priced["total"] / persons, 2) if persons and priced["known_count"] else None
    return {**priced, "persons": persons, "per_person": per_person, "unmatched": unmatched,
            "complete": not priced["unknown"] and not unmatched}


def week_cost(db: Session, monday: date) -> dict:
    """Geschatte kosten van het weekmenu (recepten geschaald + extra's), met bonusbesparing."""
    from app.api.routes import aggregate_cart

    recipes, factors, extras = planning.week_grocery_input(db, monday)
    bonus = ah_sync.bonus_for_week(db, monday)
    cart, unmatched = aggregate_cart(recipes, factors, extras)
    priced = price_cart(db, cart, _products_of(recipes, extras), bonus)
    entries = planning.week_entries(db, monday)
    household = planning.household_size(db)
    meals = sum(planning.entry_persons(e, household) for e in entries if e.kind in ("recipe", "leftover"))
    budget = planning.week_budget(db)
    actual = week_actual(db, monday)
    return {**priced, "week": str(monday), "unmatched_count": len(unmatched), "meals": meals,
            "per_meal": round(priced["total"] / meals, 2) if meals and priced["known_count"] else None,
            "bonus_period": {"start": bonus.start, "end": bonus.end} if bonus else None,
            "budget": budget or None, "budget_pct": round(100 * priced["total"] / budget) if budget else None,
            "actual": actual, "actual_pct": round(100 * actual / budget) if budget and actual is not None else None}


def week_actual(db: Session, monday: date) -> float | None:
    """Wat er in die week echt is uitgegeven (bestellingen en bonnen met bekend bedrag); None zonder ritten."""
    trips = [t for t in ah_sync.trips_since(db, monday) if t.date <= str(monday + timedelta(days=6)) and t.total is not None]
    return round(sum(t.total for t in trips), 2) if trips else None
