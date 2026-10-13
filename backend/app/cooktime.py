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
