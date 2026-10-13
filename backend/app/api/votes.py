"""Stemmen op kandidaten (D7). Contract: docs/plan-api.md. Bestelt niets."""

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app import members, planning, voting
from app.api import plan as plan_api
from app.api import routes
from app.database import get_db

router = APIRouter(prefix="/api")


def _err(message: str, status: int = 400) -> JSONResponse:
    return JSONResponse({"ok": False, "error": message}, status_code=status)


def _me_id(request: Request, db: Session) -> str | None:
    me = members.current(request, db)
    return me["id"] if me else None


class StartPayload(BaseModel):
    week: str | None = None
    recipe_ids: list[int] | None = None  # leeg = Miso kiest de kandidaten


@router.get("/vote-poll")
async def get_vote_poll(request: Request, week: str | None = None, db: Session = Depends(get_db)):
    return {"ok": True, **voting.state(db, routes.parse_week(week), _me_id(request, db))}


@router.post("/vote-poll")
async def start_vote_poll(payload: StartPayload, request: Request, db: Session = Depends(get_db)):
    monday = routes.parse_week(payload.week)
    poll = voting.start(db, monday, payload.recipe_ids)
    if not poll:
        return _err(f"Er zijn minstens {voting.MIN_CANDIDATES} recepten nodig om op te laten stemmen.")
    return {"ok": True, **voting.state(db, monday, _me_id(request, db))}


@router.delete("/vote-poll")
async def cancel_vote_poll(week: str | None = None, db: Session = Depends(get_db)):
    if not voting.cancel(db, routes.parse_week(week)):
        return _err("Er loopt geen stemronde voor deze week.", 404)
    return {"ok": True}


@router.post("/vote-poll/close")
async def close_vote_poll(payload: StartPayload, db: Session = Depends(get_db)):
    monday = routes.parse_week(payload.week)
    result = voting.close(db, monday)
    if result is None:
        return _err("Er loopt geen stemronde voor deze week.", 404)
    result.pop("entries")  # alleen de nieuwe regels; clients krijgen de hele week
    entries = plan_api.entries_json(db, planning.week_entries(db, monday))
    return {"ok": True, **result, "entries": entries, "week": str(monday), "status": routes.week_status(db, monday)}


class VotePayload(BaseModel):
    week: str | None = None
    recipe_id: int
    on: bool = True


@router.post("/votes")
async def cast_vote(payload: VotePayload, request: Request, db: Session = Depends(get_db)):
    me = _me_id(request, db)
    if not me:
        return _err("Kies eerst wie je bent, dan kun je stemmen.")
    monday = routes.parse_week(payload.week)
    error = voting.cast(db, monday, me, payload.recipe_id, payload.on)
    if error:
        return _err(error)
    return {"ok": True, **voting.state(db, monday, me)}
