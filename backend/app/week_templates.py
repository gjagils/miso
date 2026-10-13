"""Weeksjablonen (F9): een week opslaan en op een andere week terugzetten.

Alleen recept- en voorraadregels worden bewaard; restjes volgen uit "morgen opeten" bij het recept ervoor.
Vriezer-effecten (porties pakken of aanvullen) worden niet herhaald: die horen bij de dag zelf.
"""

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import planning
from app.models import PlanEntry, Recipe, WeekTemplate

MAX_TEMPLATES = 30


def snapshot(db: Session, monday: date) -> list[dict]:
    """De plannregels van een week als sjabloon-items."""
    entries = planning.week_entries(db, monday)
    rest_ids = {e.source_entry_id for e in entries if e.kind == "leftover" and e.source_entry_id}
    items: list[dict] = []
    for e in entries:
        weekday = date.fromisoformat(e.date).weekday()
        if e.kind == "recipe":
            items.append({"weekday": weekday, "kind": "recipe", "recipe_id": e.recipe_id, "persons": e.persons,
                          "rest": e.id in rest_ids})
        elif e.kind == "stock":
            items.append({"weekday": weekday, "kind": "stock", "text": e.text, "persons": e.persons,
                          "extras": e.extras})
    return items


def save(db: Session, name: str, monday: date, today: date | None = None) -> WeekTemplate | None:
    items = snapshot(db, monday)
    if not items:
        return None
    existing = db.execute(select(WeekTemplate).where(WeekTemplate.name == name)).scalars().first()
    tpl = existing or WeekTemplate(name=name)
    tpl.items = items
    tpl.created_on = str(today or date.today())
    db.add(tpl)
    db.commit()
    return tpl


def describe(db: Session, tpl: WeekTemplate) -> dict:
    items = tpl.items
    ids = {i.get("recipe_id") for i in items if i.get("recipe_id")}
    recipes = {r.id: r for r in db.execute(select(Recipe).where(Recipe.id.in_(ids))).scalars()} if ids else {}
    days = []
    for i in sorted(items, key=lambda x: x.get("weekday", 0)):
        if i["kind"] == "recipe":
            r = recipes.get(i.get("recipe_id"))
            label = r.name if r else "(recept verwijderd)"
        else:
            label = i.get("text") or "Hebben we al"
        days.append({"weekday": i.get("weekday", 0), "label": label, "missing": i["kind"] == "recipe" and i.get("recipe_id") not in recipes})
    return {"id": tpl.id, "name": tpl.name, "created_on": tpl.created_on, "count": len(items), "days": days}


def apply(db: Session, tpl: WeekTemplate, monday: date, replace: bool = False) -> dict:
    """Zet het sjabloon op de week van `monday`. Bezette dagen blijven staan, tenzij `replace`."""
    entries = planning.week_entries(db, monday)
    busy = {e.date: e for e in entries if e.kind in ("recipe", "stock")}
    rest_days = {e.date for e in entries if e.kind == "leftover"}  # een restje bezet de avond en blijft altijd staan
    placed = skipped_busy = skipped_gone = 0
    created: list[PlanEntry] = []
    for item in tpl.items:
        day = monday + timedelta(days=int(item.get("weekday", 0)))
        if str(day) in rest_days:
            skipped_busy += 1
            continue
        if str(day) in busy:
            if not replace:
                skipped_busy += 1
                continue
            db.delete(busy.pop(str(day)))
        if item["kind"] == "recipe":
            recipe = db.get(Recipe, item.get("recipe_id") or 0)
            if not recipe:
                skipped_gone += 1
                continue
            entry = PlanEntry(date=str(day), kind="recipe", recipe_id=recipe.id, persons=item.get("persons"),
                              cook_double="tomorrow" if item.get("rest") else None)
            db.add(entry)
            db.flush()
            created.append(entry)
            if item.get("rest"):
                next_day = day + timedelta(days=1)
                if next_day <= monday + timedelta(days=6):
                    db.add(PlanEntry(date=str(next_day), kind="leftover", recipe_id=recipe.id,
                                     persons=item.get("persons"), source_entry_id=entry.id))
                else:
                    entry.cook_double = None
        else:
            entry = PlanEntry(date=str(day), kind="stock", recipe_id=0, persons=item.get("persons"),
                              text=item.get("text") or "")
            entry.extras = item.get("extras") or []
            db.add(entry)
            created.append(entry)
        placed += 1
    db.commit()
    return {"placed": placed, "skipped_busy": skipped_busy, "skipped_gone": skipped_gone}
