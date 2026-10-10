"""API voor plannen met wensen per dag (zie app/wishes.py en docs/plan-gebruiksgemak.md)."""

from datetime import date, timedelta

from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import planning, wishes
from app.api import routes
from app.clients.ah import ah_client
from app.database import get_db
from app.logging_config import logger
from app.models import PlanEntry, Recipe

router = APIRouter()


class ProposePayload(BaseModel):
    week: str | None = None
    wishes: dict[str, str]  # datum -> chip of tekst


@router.post("/api/plan/propose")
async def api_propose(payload: ProposePayload, db: Session = Depends(get_db)):
    monday = routes.parse_week(payload.week)
    days = wishes.propose(db, monday, payload.wishes)
    own_ah = {rid for rid in db.execute(select(Recipe.ah_recipe_id).where(Recipe.ah_recipe_id.is_not(None))).scalars()}
    shown: set[int] = set()
    for day in days:  # minder dan 3 eigen keuzes: aanvullen uit Allerhande (snelle doordeweekse recepten eerst)
        if day["kind"] not in ("recipe", "none") or len(day["options"]) >= 3:
            continue
        query = wishes.AH_QUERY.get(day["chip"], day["chip"] if day["chip"] != "vrij" else "snel doordeweeks")
        try:
            found = await ah_client.search_recipes(query, size=12)
        except Exception as e:  # noqa: BLE001
            logger.warning("Allerhande zoeken voor wens %r mislukt: %s", query, e)
            found = []
        found = [f for f in found if f["id"] not in own_ah and f["id"] not in shown]
        found.sort(key=lambda f: (wishes.minutes(f.get("time", "")) or 60) > 45)  # stabiel: snel eerst
        for f in found[: 3 - len(day["options"])]:
            shown.add(f["id"])
            day["options"].append({"ah_recipe_id": f["id"], "name": f["title"], "image_url": f.get("image_url", ""),
                                   "total_time": f.get("time", ""), "allerhande": True})
        if day["options"]:
            day["kind"] = "recipe"
    return {"ok": True, "week": str(monday), "days": days}


class SentencePayload(BaseModel):
    week: str | None = None
    text: str


@router.post("/api/plan/wishes-text")
async def api_wishes_text(payload: SentencePayload):
    monday = routes.parse_week(payload.week)
    try:
        by_name = await wishes.parse_sentence(payload.text)
    except Exception as e:  # noqa: BLE001
        logger.warning("Wensenzin verwerken mislukt: %s", e)
        return JSONResponse({"ok": False, "error": "Miso snapte de zin niet. Kies per dag een knop."}, status_code=502)
    return {"ok": True, "wishes": wishes.day_names_to_dates(monday, by_name)}


class Choice(BaseModel):
    date: str
    kind: str  # "recipe" | "vriezer"
    recipe_id: int | None = None
    ah_recipe_id: int | None = None


class ApplyPayload(BaseModel):
    week: str | None = None
    choices: list[Choice]
    swapped: list[int] = []  # eerste voorstellen die je wegwisselde (leert Miso van)


@router.post("/api/plan/apply")
async def api_apply(payload: ApplyPayload, db: Session = Depends(get_db)):
    """Zet de gekozen voorstellen in het weekmenu (bezette dagen blijven staan)."""
    monday = routes.parse_week(payload.week)
    taken = {e.date for e in planning.week_entries(db, monday)}
    added = 0
    for c in payload.choices:
        if c.date in taken or not (str(monday) <= c.date <= str(monday + timedelta(days=6))):
            continue
        if c.kind == "vriezer":
            db.add(PlanEntry(date=c.date, kind="stock", recipe_id=0, text="Iets uit de vriezer"))
            added += 1
            continue
        rid = c.recipe_id
        if not rid and c.ah_recipe_id:
            res = await routes.import_allerhande_recipe(db, c.ah_recipe_id)
            rid = res.get("id") if res.get("ok") else None
        if rid and db.get(Recipe, rid):
            db.add(PlanEntry(date=c.date, kind="recipe", recipe_id=rid))
            added += 1
    for rid in set(payload.swapped):
        r = db.get(Recipe, rid)
        if r:
            r.swapped_count = (r.swapped_count or 0) + 1
    db.commit()
    return {"ok": True, "added": added, "status": routes.week_status(db, monday)}


def default_week(db: Session, today: date | None = None) -> date:
    """Begin van de week met nog lege doordeweekse dagen: deze week. Anders de week waarvoor je nu bestelt."""
    today = today or date.today()
    this_monday = routes.monday_of(today)
    taken = {e.date for e in planning.week_entries(db, this_monday)}
    open_weekdays = [d for d in planning.week_dates(this_monday)
                     if d >= str(today) and date.fromisoformat(d).weekday() < 5 and d not in taken]
    if today.weekday() <= 2 and open_weekdays:
        return this_monday
    return date.fromisoformat(planning.next_week_overview(db, today)["week"])


@router.get("/plannen", response_class=HTMLResponse)
async def plan_page(request: Request, week: str | None = None, db: Session = Depends(get_db)):
    if week:
        monday = routes.parse_week(week)
    else:
        monday = default_week(db)
    entries = {e.date: e for e in planning.week_entries(db, monday)}
    days = []
    for i in range(7):
        d = monday + timedelta(days=i)
        e = entries.get(str(d))
        days.append({"date": str(d), "label": routes.day_label(d), "weekend": i >= 5, "past": d < date.today(),
                     "taken": (e.text or (db.get(Recipe, e.recipe_id).name if e.recipe_id and db.get(Recipe, e.recipe_id)
                                          else "")) if e else ""})
    chips = [(k, wishes.LABELS[k]) for k in ("rijst", "pasta", "aardappel", "wraps", "noedels", "vis", "vega", "kip",
                                               "snel", "vriezer", "vrij", "overslaan")]
    return routes.templates.TemplateResponse(request, "plannen.html", {
        "week": str(monday), "prev_week": str(monday - timedelta(days=7)), "next_week": str(monday + timedelta(days=7)),
        "days": days, "chips": chips, "has_token": bool(routes._get_setting(db, "ah_user_token")
                                                        or routes._get_setting(db, "ah_refresh_token")),
        "has_api_key": bool(routes.settings.anthropic_api_key)})
