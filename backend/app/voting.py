"""Stemmen op kandidaten (D7): ouders zetten een paar recepten klaar, iedereen in het gezin stemt (maximaal
`MAX_VOTES` stemmen per persoon), en de uitslag vult de lege dagen van de week. Niets hiervan raakt AH."""

from datetime import date, timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app import members as members_mod
from app import planning
from app.models import PlanEntry, Recipe, Vote, VotePoll
from app.usage import plan_stats, preference_score

MAX_VOTES = 3
DEFAULT_CANDIDATES = 5
MIN_CANDIDATES = 2


def week_key(monday: date) -> str:
    return str(monday)


def get_poll(db: Session, monday: date) -> VotePoll | None:
    return db.execute(select(VotePoll).where(VotePoll.week == week_key(monday))).scalars().first()


def default_candidates(db: Session, monday: date, today: date | None = None, n: int = DEFAULT_CANDIDATES) -> list[int]:
    """De meest gewilde recepten die die week nog niet op het menu staan (favorieten, 👍, lang niet gegeten)."""
    today = today or date.today()
    planned = {e.recipe_id for e in planning.week_entries(db, monday) if e.recipe_id}
    stats = plan_stats(db)
    recipes = [r for r in db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars() if r.id not in planned]
    recipes.sort(key=lambda r: (-preference_score(r, stats.get(r.id), today), r.name))
    return [r.id for r in recipes[:n]]


def start(db: Session, monday: date, recipe_ids: list[int] | None = None, today: date | None = None) -> VotePoll | None:
    """Nieuwe stemronde (een bestaande voor die week wordt vervangen). None als er te weinig kandidaten zijn."""
    ids = recipe_ids if recipe_ids is not None else default_candidates(db, monday, today)
    valid = {r.id for r in db.execute(select(Recipe).where(Recipe.id.in_(ids), Recipe.archived.is_(False))).scalars()} if ids else set()
    ids = [i for i in dict.fromkeys(ids) if i in valid]
    if len(ids) < MIN_CANDIDATES:
        return None
    poll = get_poll(db, monday) or VotePoll(week=week_key(monday))
    db.execute(delete(Vote).where(Vote.week == week_key(monday)))
    poll.candidates = ids
    poll.created_on = str(today or date.today())
    db.add(poll)
    db.commit()
    return poll


def cancel(db: Session, monday: date) -> bool:
    poll = get_poll(db, monday)
    if not poll:
        return False
    db.execute(delete(Vote).where(Vote.week == week_key(monday)))
    db.delete(poll)
    db.commit()
    return True


def cast(db: Session, monday: date, member_id: str, recipe_id: int, on: bool) -> str | None:
    """Zet of haal een stem weg. Geeft een foutmelding of None."""
    poll = get_poll(db, monday)
    if not poll:
        return "Er loopt geen stemronde voor deze week."
    if recipe_id not in poll.candidates:
        return "Dit recept doet niet mee aan de stemronde."
    key = week_key(monday)
    mine = db.execute(select(Vote).where(Vote.week == key, Vote.member_id == member_id)).scalars().all()
    existing = next((v for v in mine if v.recipe_id == recipe_id), None)
    if on and not existing:
        if len(mine) >= MAX_VOTES:
            return f"Je hebt al {MAX_VOTES} stemmen uitgebracht. Haal er eerst een weg."
        db.add(Vote(week=key, recipe_id=recipe_id, member_id=member_id))
    elif not on and existing:
        db.delete(existing)
    db.commit()
    return None


def tally(db: Session, poll: VotePoll) -> dict[int, list[str]]:
    """recept-id -> lijst van gezinslid-id's die erop stemden."""
    out: dict[int, list[str]] = {rid: [] for rid in poll.candidates}
    for v in db.execute(select(Vote).where(Vote.week == poll.week)).scalars():
        if v.recipe_id in out:
            out[v.recipe_id].append(v.member_id)
    return out


def state(db: Session, monday: date, me_id: str | None = None) -> dict:
    poll = get_poll(db, monday)
    base = {"week": week_key(monday), "open": poll is not None, "max_votes": MAX_VOTES, "candidates": [],
            "my_votes": 0, "voted_count": 0, "members_total": len(members_mod.all_members(db))}
    if not poll:
        return base
    people = {m["id"]: m for m in members_mod.all_members(db)}
    votes = tally(db, poll)
    recipes = {r.id: r for r in db.execute(select(Recipe).where(Recipe.id.in_(poll.candidates))).scalars()}
    cands = []
    for rid in poll.candidates:
        r = recipes.get(rid)
        if not r:
            continue
        who = votes.get(rid, [])
        cands.append({"recipe_id": rid, "name": r.name, "image_url": r.image_url, "total_time": r.total_time,
                      "votes": len(who), "voters": [people[m]["initial"] for m in who if m in people],
                      "mine": me_id in who if me_id else False})
    cands.sort(key=lambda c: (-c["votes"], c["name"]))
    base["candidates"] = cands
    base["my_votes"] = sum(1 for c in cands if c["mine"])
    base["voted_count"] = len({m for who in votes.values() for m in who})
    return base


def _free_days(db: Session, monday: date, today: date) -> list[str]:
    taken = {e.date for e in planning.week_entries(db, monday)}  # ook een restje bezet de avond
    days = [monday + timedelta(days=i) for i in range(7)]
    days = [d for d in days if d >= today and str(d) not in taken]
    return [str(d) for d in sorted(days, key=lambda d: (d.weekday() >= 5, d))]  # doordeweeks eerst


def close(db: Session, monday: date, today: date | None = None) -> dict | None:
    """Sluit de stemronde en zet de winnaars op lege dagen (doordeweeks eerst). Recepten zonder stem komen er niet
    in. None als er geen stemronde is."""
    today = today or date.today()
    poll = get_poll(db, monday)
    if not poll:
        return None
    votes = tally(db, poll)
    stats = plan_stats(db)
    recipes = {r.id: r for r in db.execute(select(Recipe).where(Recipe.id.in_(poll.candidates))).scalars()}
    ranked = sorted((rid for rid in poll.candidates if votes.get(rid) and rid in recipes),
                    key=lambda rid: (-len(votes[rid]), -preference_score(recipes[rid], stats.get(rid), today),
                                     recipes[rid].name))
    days = _free_days(db, monday, today)
    created: list[PlanEntry] = []
    for rid, day in zip(ranked, days):
        entry = PlanEntry(date=day, kind="recipe", recipe_id=rid)
        db.add(entry)
        created.append(entry)
    placed = len(created)
    leftover = len(ranked) - placed
    db.execute(delete(Vote).where(Vote.week == poll.week))
    db.delete(poll)
    db.commit()
    return {"entries": created, "placed": placed, "no_room": max(0, leftover), "no_votes": len(poll.candidates) - len(ranked)}
