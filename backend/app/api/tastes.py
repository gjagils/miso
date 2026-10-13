"""Smaak per persoon (zie app/tastes.py): voorkeuren en afkeer per gezinslid, en voorgestelde afkeer uit 👎."""

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import members, tastes
from app.database import get_db
from app.models import MemberPreference

router = APIRouter(prefix="/api")


def _err(message: str, status: int = 400) -> JSONResponse:
    return JSONResponse({"ok": False, "error": message}, status_code=status)


def _pref_json(p: MemberPreference) -> dict:
    return {"id": p.id, "member_id": p.member_id, "term": p.term, "kind": p.kind}


def overview(db: Session) -> dict:
    people = members.all_members(db)
    prefs = tastes.preferences(db)
    return {"members": [{"id": m["id"], "name": m["name"], "role": m["role"], "color": m["color"],
                         "preferences": [_pref_json(p) for p in prefs.get(m["id"], [])]} for m in people],
            "suggestions": tastes.suggest_dislikes(db, people)}


@router.get("/preferences")
async def api_preferences(db: Session = Depends(get_db)):
    """Smaak per persoon plus voorgestelde afkeer (uit 👎) om te bevestigen of weg te wuiven."""
    return {"ok": True, **overview(db)}


class PreferenceCreate(BaseModel):
    term: str = Field(..., min_length=1, max_length=100)
    kind: str = "dislike"


@router.post("/members/{member_id}/preferences")
async def add_preference(member_id: str, payload: PreferenceCreate, db: Session = Depends(get_db)):
    """Zet "lust geen" of "is dol op" voor één persoon. Een bestaande term krijgt de nieuwe soort."""
    if member_id not in {m["id"] for m in members.all_members(db)}:
        return _err("Dit gezinslid bestaat niet.", 404)
    if payload.kind not in tastes.KINDS:
        return _err("Soort moet 'dislike' of 'like' zijn.")
    term = tastes.clean_term(payload.term)
    if len(term) < 2:
        return _err("Geef een ingrediënt, bijvoorbeeld 'paprika'.")
    row = db.execute(select(MemberPreference).where(MemberPreference.member_id == member_id,
                                                    MemberPreference.term == term)).scalar_one_or_none()
    if row:
        row.kind = payload.kind
    else:
        row = MemberPreference(member_id=member_id, term=term, kind=payload.kind)
        db.add(row)
    db.commit()
    return {"ok": True, "preference": _pref_json(row), **overview(db)}


@router.delete("/members/{member_id}/preferences/{pref_id}")
async def delete_preference(member_id: str, pref_id: int, db: Session = Depends(get_db)):
    row = db.get(MemberPreference, pref_id)
    if not row or row.member_id != member_id:
        return _err("Deze voorkeur bestaat niet.", 404)
    db.delete(row)
    db.commit()
    return {"ok": True, **overview(db)}


class Dismiss(BaseModel):
    member_id: str
    term: str


@router.post("/preferences/dismiss")
async def dismiss_suggestion(payload: Dismiss, db: Session = Depends(get_db)):
    """"Nee, dat klopt niet": Miso stelt deze afkeer niet meer voor."""
    tastes.dismiss(db, payload.member_id, payload.term)
    return {"ok": True, **overview(db)}
