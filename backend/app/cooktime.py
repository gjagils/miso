"""Kooktijd en de dag van de week: doordeweeks liever iets dat snel klaar is, in het weekend mag het langer."""

import re
from datetime import date

WEEKDAY_MAX_MIN = 45  # ma t/m do: boven deze tijd gaat er punten af
QUICK_MIN = 30
WEEKEND_FROM_MIN = 60  # za/zo: iets met tijd is juist leuk


def minutes(total_time: str) -> int | None:
    """"45 min" -> 45, "1 uur" -> 60, "1,5 uur" -> 90; geen getal -> None."""
    text = (total_time or "").lower()
    nums = [int(n) for n in re.findall(r"\d+", text)]
    if not nums:
        return None
    if "uur" in text:
        hours = float(re.search(r"\d+(?:[.,]\d+)?", text).group(0).replace(",", "."))
        return int(round(hours * 60)) if hours < 5 else nums[0]
    return nums[0]


def time_fit(total_time: str, day: str | date) -> tuple[float, str]:
    """(score, reden) voor een recept op een dag. Doordeweeks (ma t/m do): boven 45 minuten gaat er af
    (max -20), tot 30 minuten +4. Weekend: vanaf 60 minuten +4. Onbekende tijd of vrijdag: neutraal."""
    mins = minutes(total_time)
    if mins is None:
        return 0.0, ""
    weekday = (day if isinstance(day, date) else date.fromisoformat(day)).weekday()
    if weekday <= 3:
        if mins > WEEKDAY_MAX_MIN:
            return -min(20.0, (mins - WEEKDAY_MAX_MIN) * 0.5), f"duurt {mins} min, lang voor doordeweeks"
        if mins <= QUICK_MIN:
            return 4.0, "snel klaar"
    elif weekday >= 5 and mins >= WEEKEND_FROM_MIN:
        return 4.0, "heeft tijd in het weekend"
    return 0.0, ""


# ── Timers uit de bereidingsstappen ────────────────────────────────────

MAX_TIMER_SECONDS = 8 * 3600
_UNIT = r"(?:uren|uur|u\b|minuten|minuut|min\b\.?|seconden|seconde|sec\b\.?)"
_NUM = r"\d+(?:[.,]\d+)?"
_RANGE = re.compile(rf"(?P<a>{_NUM})(?:\s*(?:[-–]|tot)\s*(?P<b>{_NUM}))?\s*(?P<unit>{_UNIT})", re.I)
_WORDS = (  # "een half uur", "een kwartier"
    (re.compile(r"\b(?:een\s+)?half\s+uur\b", re.I), 1800, "half uur"),
    (re.compile(r"\b(?:een\s+)?kwartier\b", re.I), 900, "kwartier"),
)


def _label(seconds: int) -> str:
    if seconds >= 3600 and seconds % 60 == 0:
        h, m = divmod(seconds // 60, 60)
        return f"{h} uur" + (f" {m} min" if m else "")
    if seconds >= 60 and seconds % 60 == 0:
        return f"{seconds // 60} min"
    return f"{seconds} sec"


def step_timers(step: str) -> list[dict]:
    """Tijden in een bereidingsstap als timers, op volgorde van de tekst: [{"seconds": 1200, "label": "20 min"}].
    Bij een bereik ("15-20 minuten") telt de bovengrens. Ovenstanden ("180 graden") en maten ("5 cm") doen niet mee;
    meer dan 8 uur is geen kooktimer. Dubbele tijden in één stap komen één keer voor."""
    text = step or ""
    found: list[tuple[int, int, str | None]] = []  # (positie, seconden, label)
    for pattern, seconds, label in _WORDS:
        if m := pattern.search(text):
            found.append((m.start(), seconds, label))
    for m in _RANGE.finditer(text):
        value = float((m.group("b") or m.group("a")).replace(",", "."))
        unit = m.group("unit").lower()
        factor = 3600 if unit.startswith(("uur", "uren", "u")) else 1 if unit.startswith("sec") else 60
        found.append((m.start(), int(round(value * factor)), None))
    out: list[dict] = []
    seen: set[int] = set()
    for _, seconds, label in sorted(found):
        if 0 < seconds <= MAX_TIMER_SECONDS and seconds not in seen:
            seen.add(seconds)
            out.append({"seconds": seconds, "label": label or _label(seconds)})
    return out
