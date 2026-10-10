"""Plannen met wensen per dag: "maandag iets met rijst, dinsdag wraps, woensdag vriezer, donderdag lasagne".

Een wens is een chip ("rijst", "wraps", "vis", "vriezer", "vrij", "overslaan") of vrije tekst ("lasagne").
Per dag zoeken we passende recepten (gezondheidsprofiel en naam/ingrediënten), rangschikken op voorkeur
(app/usage.py) en variatie over de week, en geven het beste plus twee alternatieven.
"""

import re
from datetime import date, timedelta

import anthropic
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import llm
from app.config import settings
from app.models import PlanEntry, Recipe
from app.nutrition import get_profile
from app.usage import plan_stats, preference_score, recently_planned_ids

# chip -> (profielvoorwaarden, woorden in naam/ingrediënten)
CHIPS: dict[str, dict] = {
    "rijst": {"basis": {"rijst"}, "words": ("rijst", "nasi", "risotto", "paella", "biryani")},
    "pasta": {"basis": {"pasta"}, "words": ("pasta", "spaghetti", "penne", "lasagne", "macaroni", "tagliatelle")},
    "aardappel": {"basis": {"aardappel"}, "words": ("aardappel", "krieltjes", "stamppot", "puree", "friet")},
    "wraps": {"basis": {"wraps"}, "words": ("wrap", "tortilla", "taco", "burrito", "enchilada", "fajita", "quesadilla")},
    "noedels": {"basis": {"noedels"}, "words": ("noedel", "bami", "mie ", "ramen", "udon", "soba")},
    "vis": {"eiwit": {"vis"}, "words": ("vis", "zalm", "kabeljauw", "garnalen", "tonijn", "heek", "pangasius")},
    "vega": {"eiwit": {"vega", "vegan", "peulvruchten"}, "words": ()},
    "kip": {"eiwit": {"kip"}, "words": ("kip",)},
    "soep": {"words": ("soep",)},
    "salade": {"words": ("salade",)},
    "snel": {"max_minutes": 30, "words": ()},
}
SPECIAL = {"vriezer", "vrij", "overslaan"}
# Zoekterm bij Allerhande als eigen recepten niet genoeg keuze geven
AH_QUERY = {"rijst": "rijst", "pasta": "pasta", "aardappel": "aardappel", "wraps": "wraps", "noedels": "noedels",
            "vis": "vis", "vega": "vegetarisch", "kip": "kip", "soep": "soep", "salade": "maaltijdsalade",
            "snel": "snel"}
LABELS = {"rijst": "Rijst", "pasta": "Pasta", "aardappel": "Aardappel", "wraps": "Wraps", "noedels": "Noedels",
          "vis": "Vis", "vega": "Vega", "kip": "Kip", "soep": "Soep", "salade": "Salade", "snel": "Snel klaar",
          "vriezer": "Uit de vriezer", "vrij": "Geen idee", "overslaan": "Overslaan"}
WEEKDAY_NAMES = ["maandag", "dinsdag", "woensdag", "donderdag", "vrijdag", "zaterdag", "zondag"]
STOP = {"iets", "met", "een", "uit", "de", "het", "van", "en", "of", "lekker", "wat", "zin", "in"}


def normalize(wish: str) -> str:
    """Vrije tekst naar een chip als dat duidelijk is ("iets met rijst" -> rijst, "geen idee" -> vrij)."""
    w = (wish or "").strip().lower()
    if not w or w in ("geen idee", "maakt niet uit", "verras me", "?"):
        return "vrij"
    if w in CHIPS or w in SPECIAL:
        return w
    if "vriezer" in w or "diepvries" in w:
        return "vriezer"
    if w in ("niks", "niets", "uit eten", "weg", "afhalen", "supermarkt", "restjes"):
        return "overslaan"
    words = [t for t in re.findall(r"[a-zà-ÿ]+", w) if t not in STOP]
    if len(words) == 1:  # "iets met rijst" -> rijst; "wraps" -> wraps
        for chip, spec in CHIPS.items():
            if words[0] == chip or words[0].rstrip("s") == chip.rstrip("s"):  # "lasagne" blijft een gerecht
                return chip
    return w  # gerecht als tekst ("lasagne", "nasi goreng")


def minutes(total_time: str) -> int | None:
    nums = [int(n) for n in re.findall(r"\d+", total_time or "")]
    if not nums:
        return None
    return nums[0] * 60 if "uur" in (total_time or "").lower() and nums[0] < 5 else nums[0]


def matches(recipe: Recipe, profile: dict | None, wish: str) -> bool:
    text = f"{recipe.name} " + " ".join(i.get("text", "") for i in recipe.ingredients)
    low = text.lower()
    spec = CHIPS.get(wish)
    if spec is None:  # gerecht als tekst: alle woorden in de naam (of ingrediënten)
        words = [t for t in re.findall(r"[a-zà-ÿ]+", wish) if t not in STOP]
        name = recipe.name.lower()
        return bool(words) and (all(w in name for w in words) or all(w in low for w in words) and len(words) > 1)
    ok_profile = False
    if profile:
        if spec.get("basis") and profile.get("basis") in spec["basis"]:
            ok_profile = True
        if spec.get("eiwit") and profile.get("eiwit") in spec["eiwit"]:
            ok_profile = True
    if spec.get("max_minutes"):
        m = minutes(recipe.total_time)
        return m is not None and m <= spec["max_minutes"]
    return ok_profile or any(w in low for w in spec.get("words", ()))


def _variety_penalty(profile: dict | None, chosen: list[dict]) -> float:
    if not profile:
        return 0.0
    same = lambda key: sum(1 for p in chosen if p and p.get(key) == profile.get(key))
    return 10 * same("basis") + 8 * same("eiwit") + 5 * same("keuken")


def _health(profile: dict | None) -> float:
    if not profile:
        return 25.0  # neutraal: recept zonder profiel valt niet weg
    return profile["score"] * 8 + min(profile["groente_g"], 250) / 12 - abs(profile["kcal"] - 600) / 30


def propose(db: Session, monday: date, wishes: dict[str, str], per_day: int = 3,
            today: date | None = None) -> list[dict]:
    """wishes: {"2026-10-12": "rijst", ...}. Geeft per dag {date, wish, kind, options} (niets opgeslagen)."""
    today = today or date.today()
    stats = plan_stats(db)
    recent = recently_planned_ids(db, 14, today)
    taken = {e.date: e for e in db.execute(select(PlanEntry).where(
        PlanEntry.date >= str(monday), PlanEntry.date <= str(monday + timedelta(days=6)))).scalars()}
    recipes = db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars().all()
    profiles = {r.id: get_profile(db, r.id) for r in recipes}
    week_ids = {e.recipe_id for e in taken.values() if e.kind == "recipe"}
    chosen_profiles = [profiles.get(rid) for rid in week_ids]
    used: set[int] = set(week_ids)
    out = []
    for day in sorted(wishes):
        wish = normalize(wishes[day])
        item = {"date": day, "wish": wishes[day], "chip": wish, "label": LABELS.get(wish, wishes[day]), "options": []}
        if day in taken:
            item["kind"] = "taken"
            continue_entry = taken[day]
            item["taken"] = continue_entry.text or (db.get(Recipe, continue_entry.recipe_id).name
                                                    if continue_entry.recipe_id else "")
            out.append(item)
            continue
        if wish in ("vriezer", "overslaan"):
            item["kind"] = wish
            out.append(item)
            continue
        pool = [r for r in recipes if r.id not in used and (wish == "vrij" or matches(r, profiles[r.id], wish))]
        scored = []
        for r in pool:
            p = profiles[r.id]
            s = preference_score(r, stats.get(r.id), today) + _health(p) - _variety_penalty(p, chosen_profiles)
            if r.id in recent:
                s -= 15
            scored.append((s, r))
        scored.sort(key=lambda x: (-x[0], x[1].name))
        item["kind"] = "recipe" if scored else "none"
        item["options"] = [{"recipe_id": r.id, "name": r.name, "image_url": r.image_url, "total_time": r.total_time,
                            "favorite": bool(r.favorite)} for _, r in scored[:per_day]]
        if scored:
            used.add(scored[0][1].id)
            chosen_profiles.append(profiles[scored[0][1].id])
        out.append(item)
    return out


WISHES_PROMPT = """Je zet een korte Nederlandse zin over wat een gezin deze week wil eten om naar wensen per dag.
Antwoord ALLEEN met JSON: {"maandag": "...", "dinsdag": "...", ...} met alleen de genoemde dagen.
Gebruik per dag één van: rijst, pasta, aardappel, wraps, noedels, vis, vega, kip, soep, salade, snel, vriezer,
vrij (geen idee / maakt niet uit), overslaan (uit eten, supermarkt, restjes, niks), of anders de naam van het
gerecht in een paar woorden (bijv. "lasagne", "nasi goreng"). "door de week" = maandag t/m vrijdag."""


async def parse_sentence(text: str) -> dict[str, str]:
    """'maandag rijst, dinsdag wraps, woensdag vriezer' -> {"maandag": "rijst", ...} met het snelle model."""
    from app.clients.extractor import _parse_json

    if not settings.anthropic_api_key:
        raise ValueError("ANTHROPIC_API_KEY is niet ingesteld.")
    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
    message = await client.messages.create(
        model=await llm.model("snel"), max_tokens=500, system=WISHES_PROMPT,
        messages=[{"role": "user", "content": text[:500]}],
    )
    if message.stop_reason == "refusal":
        raise ValueError("Claude kon deze zin niet verwerken.")
    raw = _parse_json(next((b.text for b in message.content if getattr(b, "type", "") == "text"), ""))
    return {d: str(v).strip()[:60] for d, v in raw.items() if d in WEEKDAY_NAMES and str(v).strip()}


def day_names_to_dates(monday: date, by_name: dict[str, str]) -> dict[str, str]:
    return {str(monday + timedelta(days=WEEKDAY_NAMES.index(n))): w for n, w in by_name.items() if n in WEEKDAY_NAMES}
