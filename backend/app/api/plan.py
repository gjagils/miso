"""Eén plannings-API voor web en iOS: planregels (recept / restje / voorraad), vriezer, besteldag.

Contract: docs/plan-api.md. Hier wordt nooit iets bij AH besteld.
"""

from datetime import date, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import planning
from app.api import routes
from app.database import get_db
from app.models import FreezerItem, PlanEntry, Recipe

router = APIRouter(prefix="/api")

MAX_EXTRAS = 20


def _err(message: str, status: int = 400) -> JSONResponse:
    return JSONResponse({"ok": False, "error": message}, status_code=status)


def recipe_summary(r: Recipe) -> dict:
    return {"id": r.id, "name": r.name, "servings": r.servings, "total_time": r.total_time,
            "image_url": r.image_url, "gf_mode": r.gf_mode}


def entry_json(e: PlanEntry, recipes: dict[int, Recipe], household: int,
               leftovers: dict[int, list[PlanEntry]] | None = None) -> dict:
    recipe = recipes.get(e.recipe_id) if e.recipe_id else None
    persons = planning.entry_persons(e, household)
    if e.kind == "recipe":
        title = recipe.name if recipe else "Recept verwijderd"
    elif e.kind == "leftover":
        title = f"Rest van {recipe.name}" if recipe else (e.text or "Restjes")
    else:
        title = e.text or "Hebben we al"
    return {
        "entry_id": e.id,
        "date": e.date,
        "kind": e.kind,
        "title": title,
        "persons": persons,
        "persons_is_default": e.persons is None,
        "grocery_persons": planning.grocery_persons(e, household),
        "recipe_id": e.recipe_id or None,
        "recipe": recipe_summary(recipe) if recipe else None,
        "text": e.text or "",
        "extras": [{"text": x.get("text", ""), "product": (x.get("product") or {}).get("name"),
                    "product_id": (x.get("product") or {}).get("id"),
                    "product_image": (x.get("product") or {}).get("image_url", "")} for x in e.extras],
        "cook_double": e.cook_double,
        "source_entry_id": e.source_entry_id,
        "leftover_entry_ids": [x.id for x in (leftovers or {}).get(e.id, [])],
    }


def entries_json(db: Session, entries: list[PlanEntry]) -> list[dict]:
    household = planning.household_size(db)
    recipes = planning.recipes_for(db, entries)
    ids = [e.id for e in entries]
    leftovers: dict[int, list[PlanEntry]] = {}
    if ids:
        for x in db.execute(select(PlanEntry).where(PlanEntry.source_entry_id.in_(ids))).scalars():
            leftovers.setdefault(x.source_entry_id, []).append(x)
    return [entry_json(e, recipes, household, leftovers) for e in entries]


def _week_status_for(db: Session, iso: str) -> dict:
    return routes.week_status(db, routes.parse_week(iso))


def _valid_date(value: str) -> date | None:
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def _clean_extras(lines: list) -> list[dict]:
    out = []
    for x in lines[:MAX_EXTRAS]:
        text = (x.get("text") if isinstance(x, dict) else str(x or "")).strip()[:200]
        if text:
            out.append({"text": text})
    return out


def _clean_persons(value: int | None) -> int | None:
    return None if value is None else max(1, min(planning.MAX_PERSONS, int(value)))


# ── Planregels ─────────────────────────────────────────────────────────


@router.get("/plan/entries")
async def list_entries(start: str | None = None, days: int = Query(7, ge=1, le=62), week: str | None = None,
                       db: Session = Depends(get_db)):
    """Planregels vanaf `start` (default: vandaag) voor `days` dagen, of een hele `week`."""
    first = routes.parse_week(week) if week else (_valid_date(start or "") or date.today())
    last = first + timedelta(days=(7 if week else days) - 1)
    return {"ok": True, "start": str(first), "end": str(last),
            "household_size": planning.household_size(db),
            "entries": entries_json(db, planning.entries_between(db, first, last))}


class EntryCreate(BaseModel):
    date: str
    kind: Literal["recipe", "leftover", "stock"] = "recipe"
    recipe_id: int | None = None
    persons: int | None = Field(None, ge=1, le=planning.MAX_PERSONS)
    text: str | None = None
    extras: list = []  # ["pasta", ...] of [{"text": "pasta"}, ...]
    cook_double: Literal["tomorrow", "freezer"] | None = None
    freezer_item_id: int | None = None


@router.post("/plan/entries")
async def create_entry(payload: EntryCreate, db: Session = Depends(get_db)):
    day = _valid_date(payload.date)
    if not day:
        return _err("Ongeldige datum (gebruik JJJJ-MM-DD).")
    persons = _clean_persons(payload.persons)
    created: list[PlanEntry] = []
    freezer_json = None

    if payload.kind in ("recipe", "leftover"):
        recipe = db.get(Recipe, payload.recipe_id or 0)
        if not recipe:
            return _err("Recept niet gevonden.", 404)
        if payload.kind == "leftover":
            entry = PlanEntry(date=str(day), kind="leftover", recipe_id=recipe.id, persons=persons,
                              text=(payload.text or "").strip()[:300])
            db.add(entry)
            created.append(entry)
        else:
            entry = PlanEntry(date=str(day), kind="recipe", recipe_id=recipe.id, persons=persons,
                              cook_double=payload.cook_double)
            db.add(entry)
            db.flush()
            created.append(entry)
            if payload.cook_double == "tomorrow":
                rest = PlanEntry(date=str(day + timedelta(days=1)), kind="leftover", recipe_id=recipe.id,
                                 persons=persons, source_entry_id=entry.id)
                db.add(rest)
                created.append(rest)
            elif payload.cook_double == "freezer":
                item = FreezerItem(name=recipe.name, portions=persons or planning.household_size(db),
                                   added_on=str(day), from_recipe_id=recipe.id)
                db.add(item)
                db.flush()
                freezer_json = freezer_item_json(item)
    else:  # stock
        text = (payload.text or "").strip()[:300]
        if payload.freezer_item_id:
            item = db.get(FreezerItem, payload.freezer_item_id)
            if not item:
                return _err("Dit staat niet (meer) in de vriezer.", 404)
            text = text or f"{item.name} uit de vriezer"
            item.portions = max(0, item.portions - 1)
            if item.portions == 0:
                db.delete(item)
            else:
                freezer_json = freezer_item_json(item)
        if not text:
            return _err("Vul in wat jullie eten, bijvoorbeeld 'Pastasaus uit de vriezer'.")
        entry = PlanEntry(date=str(day), kind="stock", recipe_id=0, persons=persons, text=text)
        entry.extras = await routes.match_extras(db, _clean_extras(payload.extras))
        db.add(entry)
        created.append(entry)
    db.commit()
    return {"ok": True, "entries": entries_json(db, created), "freezer_item": freezer_json,
            "status": _week_status_for(db, str(day))}


class EntryUpdate(BaseModel):
    date: str | None = None
    persons: int | None = Field(None, ge=1, le=planning.MAX_PERSONS)  # null = huishoudgrootte
    text: str | None = None
    extras: list | None = None


@router.patch("/plan/entries/{entry_id}")
async def update_entry(entry_id: int, payload: EntryUpdate, db: Session = Depends(get_db)):
    entry = db.get(PlanEntry, entry_id)
    if not entry:
        return _err("Deze planregel bestaat niet (meer).", 404)
    fields = payload.model_fields_set
    old_day = date.fromisoformat(entry.date)
    weeks = {routes.monday_of(old_day)}
    leftovers = planning.leftovers_of(db, entry.id)
    if "date" in fields and payload.date:
        new_day = _valid_date(payload.date)
        if not new_day:
            return _err("Ongeldige datum (gebruik JJJJ-MM-DD).")
        entry.date = str(new_day)
        weeks.add(routes.monday_of(new_day))
        for rest in leftovers:  # "morgen opeten" schuift mee
            if rest.date == str(old_day + timedelta(days=1)):
                rest.date = str(new_day + timedelta(days=1))
    if "persons" in fields:
        entry.persons = _clean_persons(payload.persons)
        for rest in leftovers:
            rest.persons = entry.persons
    if "text" in fields and payload.text is not None:
        if entry.kind == "stock" and not payload.text.strip():
            return _err("Vul in wat jullie eten.")
        entry.text = payload.text.strip()[:300]
    if "extras" in fields and payload.extras is not None:
        if entry.kind != "stock":
            return _err("Extra boodschappen horen bij 'hebben we al'.")
        known = {x.get("text"): x for x in entry.extras}
        entry.extras = await routes.match_extras(
            db, [known.get(x["text"], x) for x in _clean_extras(payload.extras)])
    db.commit()
    changed = [entry] + leftovers
    return {"ok": True, "entry": entries_json(db, [entry])[0], "entries": entries_json(db, changed),
            "status": routes.week_status(db, routes.monday_of(date.fromisoformat(entry.date))),
            "weeks": sorted(str(w) for w in weeks)}


@router.delete("/plan/entries/{entry_id}")
async def delete_entry(entry_id: int, db: Session = Depends(get_db)):
    entry = db.get(PlanEntry, entry_id)
    if not entry:
        return _err("Deze planregel bestaat niet (meer).", 404)
    deleted = [entry.id]
    for rest in planning.leftovers_of(db, entry.id):  # restje zonder kookdag heeft geen zin
        deleted.append(rest.id)
        db.delete(rest)
    if entry.kind == "leftover" and entry.source_entry_id:
        source = db.get(PlanEntry, entry.source_entry_id)
        if source and source.cook_double == "tomorrow":
            source.cook_double = None  # niet meer dubbel inkopen
    day = entry.date
    db.delete(entry)
    db.commit()
    return {"ok": True, "deleted": deleted, "status": _week_status_for(db, day)}


# ── Volgende week en besteldag ─────────────────────────────────────────


def next_week_status(db: Session, today: date | None = None) -> dict:
    overview = planning.next_week_overview(db, today)
    status = routes.week_status(db, date.fromisoformat(overview["week"]))
    overview["list_status"] = {
        "needed": status["needed"],
        "missing_count": status["missing_count"],
        "missing": status["missing"],
        "unmatched_count": len(status["unmatched"]),
        "complete": status["complete"],
    }
    return overview


@router.get("/plan/next-week-status")
async def api_next_week_status(db: Session = Depends(get_db)):
    return {"ok": True, **next_week_status(db)}


class PlanSettings(BaseModel):
    household_size: int | None = Field(None, ge=1, le=planning.MAX_PERSONS)
    order_weekday: int | None = Field(None, ge=0, le=6)


def plan_settings(db: Session) -> dict:
    wd = planning.order_weekday(db)
    return {"household_size": planning.household_size(db), "order_weekday": wd,
            "order_weekday_name": planning.WEEKDAYS[wd]}


@router.get("/plan/settings")
async def get_plan_settings(db: Session = Depends(get_db)):
    return {"ok": True, **plan_settings(db)}


@router.patch("/plan/settings")
async def patch_plan_settings(payload: PlanSettings, db: Session = Depends(get_db)):
    if payload.household_size is not None:
        planning.set_setting(db, "household_size", str(payload.household_size))
    if payload.order_weekday is not None:
        planning.set_setting(db, "order_weekday", str(payload.order_weekday))
    return {"ok": True, **plan_settings(db)}


# ── Vriezer ────────────────────────────────────────────────────────────


def freezer_item_json(item: FreezerItem) -> dict:
    return {"id": item.id, "name": item.name, "portions": item.portions, "added_on": item.added_on,
            "from_recipe_id": item.from_recipe_id}


@router.get("/freezer")
async def list_freezer(db: Session = Depends(get_db)):
    """Wat er in de vriezer ligt (oudste eerst: dat moet als eerste op)."""
    items = db.execute(select(FreezerItem).where(FreezerItem.portions > 0)
                       .order_by(FreezerItem.added_on, FreezerItem.id)).scalars()
    return {"ok": True, "items": [freezer_item_json(i) for i in items]}


class FreezerCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=300)
    portions: int = Field(1, ge=1, le=50)
    from_recipe_id: int | None = None
    added_on: str | None = None


@router.post("/freezer")
async def add_freezer(payload: FreezerCreate, db: Session = Depends(get_db)):
    name = payload.name.strip()
    if not name:
        return _err("Geef het een naam.")
    added = _valid_date(payload.added_on or "") or date.today()
    item = FreezerItem(name=name, portions=payload.portions, added_on=str(added),
                       from_recipe_id=payload.from_recipe_id if payload.from_recipe_id and
                       db.get(Recipe, payload.from_recipe_id) else None)
    db.add(item)
    db.commit()
    return {"ok": True, "item": freezer_item_json(item)}


class FreezerUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=300)
    portions: int | None = Field(None, ge=0, le=50)


@router.patch("/freezer/{item_id}")
async def update_freezer(item_id: int, payload: FreezerUpdate, db: Session = Depends(get_db)):
    item = db.get(FreezerItem, item_id)
    if not item:
        return _err("Dit staat niet (meer) in de vriezer.", 404)
    if payload.name is not None and payload.name.strip():
        item.name = payload.name.strip()
    if payload.portions is not None:
        item.portions = payload.portions
    if item.portions <= 0:
        db.delete(item)
        db.commit()
        return {"ok": True, "item": None, "deleted": True}
    db.commit()
    return {"ok": True, "item": freezer_item_json(item), "deleted": False}


@router.delete("/freezer/{item_id}")
async def delete_freezer(item_id: int, db: Session = Depends(get_db)):
    item = db.get(FreezerItem, item_id)
    if not item:
        return _err("Dit staat niet (meer) in de vriezer.", 404)
    db.delete(item)
    db.commit()
    return {"ok": True}
