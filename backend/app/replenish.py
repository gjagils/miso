"""Waarschijnlijk op: herbestel-voorspelling uit het eigen koopgedrag (bestellingen + kassabonnen).

Geen voorraad bijhouden. Per product kijken we hoe vaak en met welk interval het gekocht wordt; is de
laatste aankoop plus het gebruikelijke interval binnen een week, dan is het "waarschijnlijk op".
Minimaal `MIN_TIMES` aankopen, anders is er geen patroon. Zegt het gezin "hebben we nog", dan schuift de
voorspelling op (`snooze`, bewaard in de instellingen).
"""

import json
import statistics
from datetime import date, timedelta

from sqlalchemy.orm import Session

from app.planning import get_setting, set_setting

MIN_TIMES = 3
HORIZON_DAYS = 7  # "binnenkort" = komt binnen een week aan de beurt
MAX_INTERVAL_DAYS = 120  # langer dan dit zien we niet als patroon (seizoensdingen, eenmalige kopen)
SNOOZE_KEY = "replenish_snooze"  # {product_id: "YYYY-MM-DD" tot wanneer "hebben we nog" geldt}


def product_stats(trips: list[dict]) -> dict[int, dict]:
    """Per product: koopmomenten (datums), aantal keer, gemiddelde hoeveelheid, naam."""
    stats: dict[int, dict] = {}
    for t in trips:
        day = t.get("date", "")
        for ln in t.get("lines") or []:
            pid = int(ln.get("product_id") or 0)
            if not pid or not day:
                continue
            s = stats.setdefault(pid, {"product_id": pid, "name": "", "dates": set(), "qty": [], "category": ""})
            s["dates"].add(day)
            s["qty"].append(float(ln.get("quantity") or 1))
            if ln.get("name") and (not s["name"] or t.get("source") == "bestelling"):
                s["name"] = ln["name"]
            if ln.get("category") and not s["category"]:
                s["category"] = ln["category"]
    return stats


def predict(trips: list[dict], today: date | None = None, snooze: dict[int, str] | None = None,
            exclude: set[int] | None = None) -> list[dict]:
    """Producten met een koopritme, gesorteerd op urgentie. Status: "op" (over tijd), "binnenkort"
    (binnen een week), "ok". `exclude`: zit al in de boodschappen van de week."""
    today = today or date.today()
    out = []
    for pid, s in product_stats(trips).items():
        if exclude and pid in exclude:
            continue
        dates = sorted(date.fromisoformat(d) for d in s["dates"])
        if len(dates) < MIN_TIMES:
            continue
        gaps = [(b - a).days for a, b in zip(dates, dates[1:]) if (b - a).days > 0]
        if not gaps:
            continue
        interval = int(round(statistics.median(gaps)))
        if interval > MAX_INTERVAL_DAYS:
            continue
        last = dates[-1]
        due = last + timedelta(days=interval)
        until = (snooze or {}).get(pid)
        if until and until >= str(today):
            due = max(due, date.fromisoformat(until))
        days_left = (due - today).days
        status = "op" if days_left <= 0 else "binnenkort" if days_left <= HORIZON_DAYS else "ok"
        out.append({"product_id": pid, "name": s["name"], "category": s["category"], "times": len(dates),
                    "interval_days": interval, "last_bought": str(last), "due_on": str(due),
                    "days_left": days_left, "status": status,
                    "avg_quantity": round(statistics.mean(s["qty"]), 1) if s["qty"] else 1.0,
                    "snoozed_until": until if until and until >= str(today) else None})
    out.sort(key=lambda x: (x["days_left"], -x["times"], x["name"].lower()))
    return out


def load_snooze(db: Session) -> dict[int, str]:
    try:
        data = json.loads(get_setting(db, SNOOZE_KEY) or "{}")
    except ValueError:
        return {}
    return {int(k): str(v) for k, v in data.items()} if isinstance(data, dict) else {}


def snooze(db: Session, product_id: int, days: int, today: date | None = None) -> str:
    """"Hebben we nog": niet meer tonen tot over `days` dagen."""
    today = today or date.today()
    data = load_snooze(db)
    data = {k: v for k, v in data.items() if v >= str(today)}  # opruimen
    until = str(today + timedelta(days=max(1, days)))
    data[int(product_id)] = until
    set_setting(db, SNOOZE_KEY, json.dumps({str(k): v for k, v in data.items()}))
    return until
