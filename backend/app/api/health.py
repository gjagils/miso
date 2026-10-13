"""Weekmenu op gezondheid en variatie: profielen per recept, weekanalyse en een gevarieerd voorstel."""

import asyncio
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import planning
from app.api import routes
from app.database import SessionLocal, get_db
from app.logging_config import logger
from app.models import PlanEntry, Recipe
from app.nutrition import analyze_week, ensure_profile, get_profile, suggest_week

router = APIRouter()

PROFILE_JOB: dict = {"running": False, "done": 0, "total": 0, "error": None}


def _week(db: Session, monday: date) -> list[PlanEntry]:
    return db.execute(select(PlanEntry).where(PlanEntry.date >= str(monday),
                                              PlanEntry.date <= str(monday + timedelta(days=6)))).scalars().all()


def _planned(db: Session, monday: date) -> list[tuple[PlanEntry, Recipe]]:
    """Gekookte recepten (restjes en voorraad tellen niet mee voor variatie)."""
    return [(e, r) for e in _week(db, monday) if e.kind == "recipe" and (r := db.get(Recipe, e.recipe_id))]


def _leftover_count(db: Session, monday: date) -> int:
    return sum(1 for e in _week(db, monday) if e.kind == "leftover")


@router.get("/api/week/health")
async def week_health(week: str | None = None, db: Session = Depends(get_db)):
    monday = routes.parse_week(week)
    planned = _planned(db, monday)
    for _, r in planned:  # ontbrekende profielen nu schatten (alleen voor deze week: weinig aanroepen)
        await ensure_profile(db, r)
    rows = [(e.date, get_profile(db, r.id)) for e, r in planned]
    return {"week": str(monday), **analyze_week(rows, leftover_days=_leftover_count(db, monday)),
            "recepten": [{"date": e.date, "entry_id": e.id, "recipe_id": r.id, "name": r.name,
                          "profiel": get_profile(db, r.id)} for e, r in planned]}


class SuggestPayload(BaseModel):
    week: str | None = None


@router.post("/api/week/suggest")
async def week_suggest(payload: SuggestPayload, db: Session = Depends(get_db)):
    """Voorstel voor de lege dagen (vanaf vandaag). Slaat niets op; de app plant pas na bevestiging."""
    monday = routes.parse_week(payload.week)
    planned = _planned(db, monday)
    taken = {e.date for e in _week(db, monday)}  # ook restjes- en voorraaddagen zijn bezet
    start = max(monday, date.today())
    empty = [str(d) for i in range(7) if (d := monday + timedelta(days=i)) >= start and str(d) not in taken]
    last_weeks = db.execute(select(PlanEntry.recipe_id).where(PlanEntry.date >= str(monday - timedelta(days=14)),
                                                              PlanEntry.date < str(monday),
                                                              PlanEntry.kind == "recipe")).scalars().all()
    from app.usage import plan_stats, preference_score

    stats = plan_stats(db)
    candidates = [(r, p) for r in db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars()
                  if (p := get_profile(db, r.id))]
    prefs = {r.id: preference_score(r, stats.get(r.id)) for r, _ in candidates}
    plan = [{"recipe_id": r.id, "profiel": get_profile(db, r.id)} for _, r in planned]
    chosen = suggest_week(plan, candidates, empty, set(last_weeks), prefs,
                          suggest_context(db, [r for r, _ in candidates], monday, stats),
                          kids_weekday=planning.kids_weekday(db))
    missing = db.query(Recipe).count() - len(candidates)
    return {"ok": True, "voorstel": chosen, "zonder_profiel": missing,
            "analyse": analyze_week([(e.date, get_profile(db, r.id)) for e, r in planned] +
                                    [(c["date"], c["profiel"]) for c in chosen],
                                    leftover_days=_leftover_count(db, monday))}


def suggest_context(db: Session, recipes: list[Recipe], monday: date, stats: dict | None = None) -> dict[int, dict]:
    """Wat het voorstel per recept nog meer weet, voor de uitleg en de extra termen: fans en duimpjes
    (app/family, usage), wensen, bonus van die week (ah_sync), laatst gegeten, kosten per persoon."""
    from app import ah_sync, costs, members, planning
    from app.api.family import fans_map
    from app.clients.ah_data import score_recipes
    from app.models import Wish
    from app.usage import last_eaten, plan_stats

    stats = stats if stats is not None else plan_stats(db)
    today = date.today()
    ctx: dict[int, dict] = {r.id: {} for r in recipes}
    initials = fans_map(db)
    names = {m["initial"]: m["name"] for m in members.all_members(db)}
    member_names = {m["id"]: m["name"] for m in members.all_members(db)}
    for r in recipes:
        c = ctx[r.id]
        c["fans"] = [names.get(i, i) for i in initials.get(r.id, [])]
        c["thumbs_up"], c["thumbs_down"] = r.thumbs_up or 0, r.thumbs_down or 0
        eaten = last_eaten(r, stats.get(r.id), today)
        c["last_cooked"] = eaten
        c["never_cooked"] = not eaten and not (stats.get(r.id) or {}).get("planned") and not r.cooked_count
    from app import tastes

    for rid, hit in tastes.taste_hits(db, recipes, members.all_members(db)).items():
        ctx[rid].update(dislike_terms=hit["dislikes"], like_terms=hit["likes"])
    for w in db.execute(select(Wish).where(Wish.done_on.is_(None), Wish.recipe_id.is_not(None))).scalars():
        if w.recipe_id in ctx:
            ctx[w.recipe_id].setdefault("wishes", []).append(member_names.get(w.member_id, w.member_id or "iemand"))
    bonus = ah_sync.bonus_for_week(db, monday)
    if bonus and bonus.products:
        for row in score_recipes([{"id": r.id, "ingredients": r.ingredients} for r in recipes], bonus.products):
            ctx[row["id"]].update(bonus_saving=row.get("saving") or 0, bonus_count=row["bonus_count"])
    household = planning.household_size(db)
    for r in recipes:
        try:
            cost = costs.recipe_cost(db, r, household, bonus, monday)
        except Exception as e:  # noqa: BLE001 - kosten zijn een extra, geen voorwaarde
            logger.warning("Kosten voor recept %s mislukt: %s", r.id, e)
            continue
        if cost["per_person"] is not None and cost["known_count"] >= 3:
            ctx[r.id]["cost_pp"] = cost["per_person"]
    return ctx


async def _profile_all(force: bool) -> None:
    PROFILE_JOB.update(running=True, done=0, error=None)
    try:
        with SessionLocal() as db:
            ids = [r.id for r in db.execute(select(Recipe)).scalars()]
            PROFILE_JOB["total"] = len(ids)
            for rid in ids:
                recipe = db.get(Recipe, rid)
                if force or get_profile(db, rid) is None:
                    await ensure_profile(db, recipe)
                PROFILE_JOB["done"] += 1
    except Exception as e:  # noqa: BLE001
        PROFILE_JOB["error"] = str(e)
        logger.error("Profiling all recipes failed: %s", e)
    finally:
        PROFILE_JOB["running"] = False


@router.post("/api/profiles/refresh")
async def profiles_refresh(force: bool = False):
    if not PROFILE_JOB["running"]:
        asyncio.create_task(_profile_all(force))
    return {"ok": True, "job": PROFILE_JOB}


@router.get("/api/profiles/status")
async def profiles_status(db: Session = Depends(get_db)):
    from app.models import RecipeProfile
    return {"job": PROFILE_JOB, "met_profiel": db.query(RecipeProfile).count(), "recepten": db.query(Recipe).count()}
