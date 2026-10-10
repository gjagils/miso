"""Gezinsleden: "Wie ben jij?" na de pincode. Geen wachtwoord per persoon (het is één gezin), wel een rol:
"ouder" mag alles, "kind" kan wensen doorgeven en favorieten zetten maar niets wissen of bestellen.

Wie er tikt staat in de cookie `miso_member` (web) of de header `X-Miso-Member` (app).
"""

import json
import re

from fastapi import Request
from sqlalchemy.orm import Session

DEFAULT = [
    {"id": "gerd-jan", "name": "Gerd-Jan", "role": "ouder"},
    {"id": "nelleke", "name": "Nelleke", "role": "ouder"},
    {"id": "hannah", "name": "Hannah", "role": "kind"},
    {"id": "suze", "name": "Suze", "role": "kind"},
]
COLORS = ["#FF8A00", "#0E2A47", "#7BC8A4", "#B79CED", "#E86A5A", "#3BA3D0"]


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "lid"


def all_members(db: Session) -> list[dict]:
    from app.api.routes import _get_setting

    raw = _get_setting(db, "members")
    try:
        members = json.loads(raw) if raw else DEFAULT
    except ValueError:
        members = DEFAULT
    return [{**m, "initial": m["name"][:1].upper(), "color": COLORS[i % len(COLORS)]} for i, m in enumerate(members)]


def save_members(db: Session, members: list[dict]) -> list[dict]:
    from app.api.routes import _set_setting

    clean, seen = [], set()
    for m in members:
        name = str(m.get("name", "")).strip()[:30]
        if not name:
            continue
        mid = slug(m.get("id") or name)
        while mid in seen:
            mid += "-2"
        seen.add(mid)
        clean.append({"id": mid, "name": name, "role": "kind" if m.get("role") == "kind" else "ouder"})
    _set_setting(db, "members", json.dumps(clean or DEFAULT, ensure_ascii=False))
    return all_members(db)


def current(request: Request, db: Session) -> dict | None:
    mid = request.headers.get("x-miso-member") or request.cookies.get("miso_member") or ""
    return next((m for m in all_members(db) if m["id"] == mid), None)


def is_kid(request: Request, db: Session) -> bool:
    m = current(request, db)
    return bool(m and m["role"] == "kind")
