"""Weekmenu op gezondheid en variatie: profielen per recept, weekanalyse en een gevarieerd voorstel."""

import asyncio
from datetime import date, timedelta

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

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
    candidates = [(r, p) for r in db.execute(select(Recipe)).scalars() if (p := get_profile(db, r.id))]
    plan = [{"recipe_id": r.id, "profiel": get_profile(db, r.id)} for _, r in planned]
    chosen = suggest_week(plan, candidates, empty, set(last_weeks))
    missing = db.query(Recipe).count() - len(candidates)
    return {"ok": True, "voorstel": chosen, "zonder_profiel": missing,
            "analyse": analyze_week([(e.date, get_profile(db, r.id)) for e, r in planned] +
                                    [(c["date"], c["profiel"]) for c in chosen],
                                    leftover_days=_leftover_count(db, monday))}


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
