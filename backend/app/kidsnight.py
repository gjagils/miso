"""Kids-kookavond (D8): een vaste weekdag waarop de kinderen meekoken. Recepten met de vlag "makkelijk met kinderen"
krijgen die avond voorrang in de voorstellen. Verandert niets aan wat al gepland staat."""

from datetime import date

BONUS_WEEK = 8.0  # "gevarieerde week": schaal van nutrition.suggest_week
BONUS_PROPOSE = 18.0  # "Stel recepten voor": schaal van wishes.propose
WHY = "makkelijk met kinderen"


def is_kids_day(day: str, kids_weekday: int | None) -> bool:
    if kids_weekday is None:
        return False
    try:
        return date.fromisoformat(day).weekday() == kids_weekday
    except ValueError:
        return False


def fit(recipe, day: str, kids_weekday: int | None, bonus: float) -> tuple[float, str]:
    """(extra score, reden). Alleen op de kids-avond en alleen voor recepten met de vlag."""
    if getattr(recipe, "kid_friendly", False) and is_kids_day(day, kids_weekday):
        return bonus, WHY
    return 0.0, ""
