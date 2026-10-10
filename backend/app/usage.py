"""Leren van gebruik: hoe vaak een recept gepland/gekookt is, favorieten, duimpjes, en opruimen.

Bewust een uitlegbare optelsom in plaats van machine learning:
  favoriet +30 · 👍 +10 per keer (max +30) · 👎 −25 per keer · vaak gepland +2 per keer (max +10)
  recent gegeten (< 14 dagen) −20 · vaak weggewisseld −5 per keer (max −15)
"""

from datetime import date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import PlanEntry, Recipe


def plan_stats(db: Session) -> dict[int, dict]:
    """Per recept: aantal keer ingepland (gekookt-regels, geen restjes) en eerste/laatste datum."""
    rows = db.execute(
        select(PlanEntry.recipe_id, func.count(), func.min(PlanEntry.date), func.max(PlanEntry.date))
        .where(PlanEntry.kind == "recipe").group_by(PlanEntry.recipe_id)
    ).all()
    return {rid: {"planned": n, "first_planned": first, "last_planned": last} for rid, n, first, last in rows}


def last_eaten(recipe: Recipe, stats: dict | None, today: date) -> str | None:
    dates = [d for d in ((stats or {}).get("last_planned"), recipe.last_cooked) if d and d <= str(today)]
    return max(dates) if dates else None


def preference_score(recipe: Recipe, stats: dict | None, today: date | None = None) -> float:
    today = today or date.today()
    s = 30.0 if recipe.favorite else 0.0
    s += min(30, 10 * (recipe.thumbs_up or 0)) - 25 * (recipe.thumbs_down or 0)
    s += min(10, 2 * ((stats or {}).get("planned", 0)))
    s -= min(15, 5 * (recipe.swapped_count or 0))
    eaten = last_eaten(recipe, stats, today)
    if eaten and (today - date.fromisoformat(eaten)).days < 14:
        s -= 20
    return s


def review_list(db: Session, today: date | None = None) -> dict:
    """Recepten om kritisch te bekijken: nooit of lang niet gekozen terwijl er wel veel gepland wordt."""
    today = today or date.today()
    stats = plan_stats(db)
    total_plans = sum(v["planned"] for v in stats.values())
    out = []
    for r in db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars():
        st = stats.get(r.id, {})
        planned = st.get("planned", 0)
        eaten = last_eaten(r, st, today)
        created = r.created_at.date() if isinstance(r.created_at, datetime) else today
        age_days = (today - created).days
        idle_days = (today - date.fromisoformat(eaten)).days if eaten else age_days
        kept_recently = r.reviewed_on and (today - date.fromisoformat(r.reviewed_on)).days < 180
        reason = None
        if planned == 0 and r.cooked_count == 0:
            reason = "Nog nooit gekozen"
        elif idle_days > 180:
            reason = f"Al {idle_days // 30} maanden niet gegeten"
        elif r.thumbs_down > r.thumbs_up:
            reason = "Vaker 👎 dan 👍"
        if reason and not kept_recently and not r.favorite:
            out.append({"id": r.id, "name": r.name, "image_url": r.image_url, "reason": reason,
                        "planned": planned, "cooked": r.cooked_count, "thumbs_up": r.thumbs_up,
                        "thumbs_down": r.thumbs_down, "last_eaten": eaten, "age_days": age_days,
                        "by_heart": r.by_heart})
    out.sort(key=lambda x: (x["planned"] + x["cooked"], -x["age_days"]))
    return {"total_plans": total_plans, "recipes": out}


def mark_cooked(recipe: Recipe, today: date | None = None) -> None:
    today = str(today or date.today())
    if recipe.last_cooked != today:  # één keer per dag tellen
        recipe.cooked_count = (recipe.cooked_count or 0) + 1
        recipe.last_cooked = today


def recently_planned_ids(db: Session, days: int = 14, today: date | None = None) -> set[int]:
    today = today or date.today()
    since = str(today - timedelta(days=days))
    return set(db.execute(select(PlanEntry.recipe_id).where(PlanEntry.kind == "recipe", PlanEntry.date >= since,
                                                             PlanEntry.date <= str(today))).scalars())
