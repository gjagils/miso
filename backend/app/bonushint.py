"""Bonushint (A5): hoeveel eigen recepten zitten volgende week (deels) in de bonus? Leest alleen de lokale
bonustabel (`ah_bonus_periods`); er wordt niets bij AH opgehaald. De iOS-app maakt er vrijdag een melding van,
de website toont dezelfde zin in de banner "Volgende week"."""

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import wishes
from app.models import Recipe

MIN_SAVING = 0.50  # onder dit voordeel (euro) telt een recept niet als "in de bonus"
MAX_NAMES = 3


def _money(value: float) -> str:
    return f"€{value:.2f}".replace(".", ",")


def next_week(db: Session, today: date | None = None) -> dict:
    """{"count", "saving", "names", "message"}; `message` is leeg als er (nog) geen bonus bekend is."""
    today = today or date.today()
    monday = today - timedelta(days=today.weekday()) + timedelta(days=7)
    recipes = list(db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars())
    savings = wishes._bonus_savings(db, recipes, monday)
    hits = sorted(((s, r) for r in recipes if (s := savings.get(r.id, 0.0)) >= MIN_SAVING), key=lambda x: -x[0])
    out = {"count": len(hits), "saving": round(sum(s for s, _ in hits), 2), "names": [r.name for _, r in hits[:MAX_NAMES]],
           "message": ""}
    if hits:
        names = out["names"]
        listed = names[0] if len(names) == 1 else ", ".join(names[:-1]) + " en " + names[-1]
        more = f" en {len(hits) - len(names)} andere" if len(hits) > len(names) else ""
        out["message"] = (f"{len(hits)} {'recept' if len(hits) == 1 else 'recepten'} van jullie "
                          f"{'zit' if len(hits) == 1 else 'zitten'} volgende week in de bonus "
                          f"(samen ongeveer {_money(out['saving'])} voordeel): {listed}{more}.")
    return out
