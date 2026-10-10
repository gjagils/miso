"""Weekplanning: personen, schalen van boodschappen, restjes, voorraad en besteldag.

Een planregel (PlanEntry) is dag + soort + personen:
- "recipe": recept koken voor `persons` (leeg = huishoudgrootte). Met `cook_double` (morgen opeten of
  naar de vriezer) wordt er voor twee keer zoveel personen ingekocht.
- "leftover": rest van een eerder gekookt recept. Kost geen boodschappen.
- "stock": "uit de vriezer / hebben we al" met vrije tekst en optionele extra boodschappen (aantal 1).
"""

import math
import re
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import AppSetting, PlanEntry, Recipe

DEFAULT_HOUSEHOLD = 4
DEFAULT_SERVINGS = 4
DEFAULT_ORDER_WEEKDAY = 6  # zondag
MAX_PERSONS = 20
WEEKDAYS = ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"]
SCALE_UP_THRESHOLD = 1.5  # niet-vergelijkbare hoeveelheden pas ophogen vanaf 1,5x


# ── Instellingen ───────────────────────────────────────────────────────


def get_setting(db: Session, key: str) -> str:
    from app.secretbox import unseal

    row = db.execute(select(AppSetting).where(AppSetting.key == key)).scalar_one_or_none()
    return unseal(key, row.value) if row else ""


def set_setting(db: Session, key: str, value: str) -> None:
    from app.secretbox import seal

    value = seal(key, value)  # AH-/Mealie-tokens versleuteld als MISO_SECRET gezet is
    row = db.execute(select(AppSetting).where(AppSetting.key == key)).scalar_one_or_none()
    if row:
        row.value = value
    else:
        db.add(AppSetting(key=key, value=value))
    db.commit()


def _int_setting(db: Session, key: str, default: int, lo: int, hi: int) -> int:
    try:
        value = int(get_setting(db, key))
    except ValueError:
        return default
    return value if lo <= value <= hi else default


def household_size(db: Session) -> int:
    return _int_setting(db, "household_size", DEFAULT_HOUSEHOLD, 1, MAX_PERSONS)


def order_weekday(db: Session) -> int:
    return _int_setting(db, "order_weekday", DEFAULT_ORDER_WEEKDAY, 0, 6)


# ── Schalen ────────────────────────────────────────────────────────────


def recipe_servings(recipe: Recipe | None) -> int:
    """Aantal personen van het recept ("4 personen", "4", "4-6 pers.") -> 4; onbekend -> 4."""
    m = re.search(r"\d+", (recipe.servings if recipe else "") or "")
    n = int(m.group(0)) if m else 0
    return n if 1 <= n <= 50 else DEFAULT_SERVINGS


def scale_factor(persons: int, recipe: Recipe | None) -> float:
    return max(1, persons) / recipe_servings(recipe)


def scale_quantity(qty: int, factor: float) -> int:
    """Aantal verpakkingen zonder vergelijkbare hoeveelheid: alleen ophogen vanaf 1,5x, nooit minder dan 1."""
    qty = max(1, int(qty or 1))
    if factor >= SCALE_UP_THRESHOLD:
        return max(1, math.ceil(qty * factor - 1e-9))
    return qty


def entry_persons(entry: PlanEntry, household: int) -> int:
    return entry.persons or household


def grocery_persons(entry: PlanEntry, household: int) -> int:
    """Voor hoeveel personen er voor deze planregel wordt ingekocht."""
    if entry.kind != "recipe":
        return 0
    persons = entry_persons(entry, household)
    return persons * 2 if entry.cook_double in ("tomorrow", "freezer") else persons


# ── Week ───────────────────────────────────────────────────────────────


def week_dates(monday: date) -> list[str]:
    return [str(monday + timedelta(days=i)) for i in range(7)]


def entries_between(db: Session, start: date, end: date) -> list[PlanEntry]:
    return list(db.execute(
        select(PlanEntry).where(PlanEntry.date >= str(start), PlanEntry.date <= str(end))
        .order_by(PlanEntry.date, PlanEntry.id)
    ).scalars())


def week_entries(db: Session, monday: date) -> list[PlanEntry]:
    return entries_between(db, monday, monday + timedelta(days=6))


def recipes_for(db: Session, entries: list[PlanEntry]) -> dict[int, Recipe]:
    ids = {e.recipe_id for e in entries if e.recipe_id}
    if not ids:
        return {}
    return {r.id: r for r in db.execute(select(Recipe).where(Recipe.id.in_(ids))).scalars()}


def grocery_input(db: Session, entries: list[PlanEntry]) -> tuple[list[Recipe], list[float], list[dict]]:
    """(recepten, schaalfactor per recept, extra boodschappen) voor aggregate_cart."""
    household = household_size(db)
    recipes = recipes_for(db, entries)
    out_recipes: list[Recipe] = []
    factors: list[float] = []
    extras: list[dict] = []
    for e in entries:
        if e.kind == "recipe" and e.recipe_id in recipes:
            r = recipes[e.recipe_id]
            out_recipes.append(r)
            factors.append(scale_factor(grocery_persons(e, household), r))
        elif e.kind == "stock":
            extras.extend(x for x in e.extras if (x.get("text") or "").strip())
    return out_recipes, factors, extras


def week_grocery_input(db: Session, monday: date) -> tuple[list[Recipe], list[float], list[dict]]:
    return grocery_input(db, week_entries(db, monday))


def leftovers_of(db: Session, entry_id: int) -> list[PlanEntry]:
    return list(db.execute(select(PlanEntry).where(PlanEntry.source_entry_id == entry_id)).scalars())


# ── Besteldag ──────────────────────────────────────────────────────────


def order_message(planned: int, days_until: int, weekday: int) -> str:
    name = WEEKDAYS[weekday]
    if days_until == 0:
        when = f"vandaag is het {name} (besteldag)"
    elif days_until == 1:
        when = f"morgen is het {name} (besteldag)"
    else:
        when = f"nog {days_until} dagen tot {name} (besteldag)"
    return f"Volgende week: {planned} van 5 doordeweekse dagen gepland · {when}"


def next_week_overview(db: Session, today: date | None = None) -> dict:
    """Hoe staat volgende week ervoor (zonder lijstje-status; die voegt de API toe)."""
    today = today or date.today()
    weekday = order_weekday(db)
    monday = today - timedelta(days=today.weekday()) + timedelta(days=7)
    days_until = (weekday - today.weekday()) % 7
    dates = week_dates(monday)
    taken = {e.date for e in week_entries(db, monday)}
    planned = sum(1 for d in dates if d in taken)
    weekdays_planned = sum(1 for d in dates[:5] if d in taken)
    return {
        "weekdays_planned": weekdays_planned,
        "ready": weekdays_planned == 5,  # doordeweeks is de focus; het weekend hoeft niet
        "order_day": weekday,
        "order_day_name": WEEKDAYS[weekday],
        "days_until_order": days_until,
        "week": str(monday),
        "planned_days": planned,
        "total_days": 7,
        "missing_dates": [d for d in dates if d not in taken],
        "prominent": days_until <= 2,
        "message": order_message(weekdays_planned, days_until, weekday),
    }


_AMOUNT = re.compile(r"^\s*(\d+/\d+|\d+(?:[.,]\d+)?(?:\s*-\s*\d+(?:[.,]\d+)?)?|[½¼¾])")
_FRACTIONS = {"½": 0.5, "¼": 0.25, "¾": 0.75}


def scale_line(text: str, factor: float) -> str:
    """'200 g kipfilet' x2 -> '400 g kipfilet'; '1/2 ui' x2 -> '1 ui'. Alleen het getal vooraan."""
    if abs(factor - 1) < 0.01:
        return text
    m = _AMOUNT.match(text or "")
    if not m:
        return text

    def num(s: str) -> float:
        s = s.strip()
        if s in _FRACTIONS:
            return _FRACTIONS[s]
        if "/" in s:
            a, b = s.split("/")
            return float(a) / float(b)
        return float(s.replace(",", "."))

    def fmt(x: float) -> str:
        if abs(x - round(x)) < 0.05:
            return str(int(round(x)))
        for frac, sym in ((0.5, "½"), (0.25, "¼"), (0.75, "¾")):
            if abs(x - int(x) - frac) < 0.05:
                return f"{int(x) or ''}{sym}"
        return f"{x:.1f}".replace(".", ",")

    raw = m.group(1)
    parts = [p for p in re.split(r"\s*-\s*", raw)] if "-" in raw else [raw]
    scaled = "-".join(fmt(num(p) * factor) for p in parts)
    return scaled + text[m.end():]


def cook_hints(recipe) -> dict:
    """Eerlijke tijd en 'zet eerst de oven aan' uit de bereiding ("bak 30 min. in de oven op 200 °C")."""
    raw = " ".join(recipe.instructions or [])
    text = raw.lower()
    temp = re.search(r"(\d{3})\s*(?:°|graden)", text)
    oven_min = 0
    for sentence in (x.lower() for x in re.split(r"(?<=[.!?])\s+(?=[A-Z])", raw)):  # "ca. 30 min." breekt niet
        if "oven" in sentence:
            mins = [int(m) for m in re.findall(r"(\d{1,3})\s*(?:-\s*\d+\s*)?min", sentence)]
            oven_min = max([oven_min, *mins])
    listed = re.search(r"\d+", recipe.total_time or "")
    listed_min = int(listed.group(0)) if listed else 0
    est = listed_min
    if oven_min and listed_min < oven_min + 10:
        est = listed_min + oven_min  # opgegeven tijd is vaak alleen het snijwerk
    return {"minutes": est or None, "oven_min": oven_min or None, "oven_temp": temp.group(1) if temp else None,
            "longer": bool(est and listed_min and est > listed_min + 5)}
