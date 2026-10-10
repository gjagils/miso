"""Gezinsleden ("Wie ben jij?"), favorieten en wensen per persoon. Zie app/members.py."""

from datetime import date

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import members
from app.api import routes
from app.database import SessionLocal, get_db
from app.models import Recipe, RecipeFavorite, Wish

router = APIRouter()

# Wat een kind niet mag (method, pad-prefix): wissen, bestellen, beheer. Wensen en favorieten mag wel.
KID_BLOCKED = [("DELETE", "/api/recipes/"), ("POST", "/recipe/"), ("DELETE", "/api/plan/entries/"),
               ("PATCH", "/api/plan/entries/"), ("POST", "/api/plan/sync"), ("POST", "/api/plan/apply"),
               ("POST", "/api/basket/"), ("POST", "/api/cart/"), ("POST", "/api/packs/"), ("PUT", "/api/members"),
               ("POST", "/api/missing/assign"), ("POST", "/api/recipes/") ]
KID_ALLOWED = ("/feedback", "/cooked", "/photo")  # binnen POST /api/recipes/...


def kid_blocked(request: Request) -> bool:
    path, method = request.url.path, request.method
    if not (request.headers.get("x-miso-member") or request.cookies.get("miso_member")):
        return False  # niemand gekozen: gedraagt zich als ouder (oude app, eerste keer)
    for m, prefix in KID_BLOCKED:
        if method == m and path.startswith(prefix):
            if prefix == "/api/recipes/" and method == "POST" and path.endswith(KID_ALLOWED):
                return False
            if prefix == "/recipe/" and not path.endswith("/delete"):
                return False
            with SessionLocal() as db:
                return members.is_kid(request, db)
    if method == "PATCH" and path.startswith("/api/recipes/") and path.endswith("/flags"):
        return False  # favoriet zetten mag; opruimen/archiveren wordt hieronder in de route zelf gecheckt
    return False


def fans_map(db: Session) -> dict[int, list[str]]:
    """recept-id -> initialen van wie het een favoriet vindt."""
    names = {m["id"]: m["initial"] for m in members.all_members(db)}
    out: dict[int, list[str]] = {}
    for f in db.execute(select(RecipeFavorite)).scalars():
        if f.member_id in names:
            out.setdefault(f.recipe_id, []).append(names[f.member_id])
    return out


def set_favorite(db: Session, recipe: Recipe, member: dict | None, on: bool) -> None:
    if member:
        row = db.execute(select(RecipeFavorite).where(RecipeFavorite.recipe_id == recipe.id,
                                                      RecipeFavorite.member_id == member["id"])).scalars().first()
        if on and not row:
            db.add(RecipeFavorite(recipe_id=recipe.id, member_id=member["id"]))
        elif not on and row:
            db.delete(row)
        db.flush()
        recipe.favorite = db.execute(select(RecipeFavorite).where(RecipeFavorite.recipe_id == recipe.id)).first() is not None
    else:
        recipe.favorite = on


# ── Wie ben jij? ───────────────────────────────────────────────────────


@router.get("/wie", response_class=HTMLResponse)
async def who_page(request: Request, db: Session = Depends(get_db)):
    return routes.templates.TemplateResponse(request, "wie.html", {"members": members.all_members(db),
                                                                   "current": members.current(request, db)})


@router.post("/wie")
async def who_choose(member: str = Form(""), db: Session = Depends(get_db)):
    ids = {m["id"] for m in members.all_members(db)}
    resp = RedirectResponse("/", status_code=303)
    if member in ids:
        resp.set_cookie("miso_member", member, max_age=60 * 60 * 24 * 365, samesite="lax")
    return resp


@router.get("/api/members")
async def api_members(request: Request, db: Session = Depends(get_db)):
    return {"members": members.all_members(db), "current": members.current(request, db)}


class MembersPayload(BaseModel):
    members: list[dict]


@router.put("/api/members")
async def api_save_members(payload: MembersPayload, db: Session = Depends(get_db)):
    return {"ok": True, "members": members.save_members(db, payload.members)}


# ── Wensen ─────────────────────────────────────────────────────────────


class WishPayload(BaseModel):
    recipe_id: int | None = None
    text: str = ""


def wish_json(db: Session, w: Wish, names: dict[str, str]) -> dict:
    r = db.get(Recipe, w.recipe_id) if w.recipe_id else None
    return {"id": w.id, "member": names.get(w.member_id, ""), "member_id": w.member_id, "text": w.text,
            "recipe_id": w.recipe_id, "recipe_name": routes._short_name(r.name) if r else "",
            "image_url": r.image_url if r else "", "created_on": w.created_on}


def open_wishes(db: Session) -> list[dict]:
    names = {m["id"]: m["name"] for m in members.all_members(db)}
    rows = db.execute(select(Wish).where(Wish.done_on.is_(None)).order_by(Wish.id.desc())).scalars().all()
    return [wish_json(db, w, names) for w in rows]


@router.get("/api/wishes")
async def api_wishes(db: Session = Depends(get_db)):
    return {"wishes": open_wishes(db)}


@router.post("/api/wishes")
async def api_add_wish(payload: WishPayload, request: Request, db: Session = Depends(get_db)):
    text = payload.text.strip()[:200]
    if not payload.recipe_id and not text:
        return JSONResponse({"ok": False, "error": "Kies een recept of typ waar je zin in hebt."}, status_code=400)
    if payload.recipe_id and not db.get(Recipe, payload.recipe_id):
        return JSONResponse({"ok": False, "error": "Recept niet gevonden."}, status_code=404)
    member = members.current(request, db)
    mid = member["id"] if member else ""
    dup = db.execute(select(Wish).where(Wish.done_on.is_(None), Wish.member_id == mid,
                                        Wish.recipe_id == payload.recipe_id, Wish.text == text)).scalars().first()
    if not dup:
        db.add(Wish(member_id=mid, recipe_id=payload.recipe_id, text=text, created_on=str(date.today())))
        db.commit()
    return {"ok": True, "wishes": open_wishes(db)}


@router.post("/api/wishes/{wish_id}/done")
async def api_wish_done(wish_id: int, db: Session = Depends(get_db)):
    w = db.get(Wish, wish_id)
    if w:
        w.done_on = str(date.today())
        db.commit()
    return {"ok": True, "wishes": open_wishes(db)}


@router.delete("/api/wishes/{wish_id}")
async def api_wish_delete(wish_id: int, db: Session = Depends(get_db)):
    w = db.get(Wish, wish_id)
    if w:
        db.delete(w)
        db.commit()
    return {"ok": True, "wishes": open_wishes(db)}
