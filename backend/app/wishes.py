"""Plannen met wensen per dag: "maandag iets met rijst, dinsdag wraps, woensdag vriezer, donderdag lasagne".

Een wens is een chip ("rijst", "wraps", "vis", "vriezer", "vrij", "overslaan") of vrije tekst ("lasagne").
Per dag zoeken we passende recepten (gezondheidsprofiel en naam/ingrediënten), rangschikken op voorkeur
(app/usage.py) en variatie over de week, en geven het beste plus twee alternatieven.
"""

import hashlib
import re
from datetime import date, timedelta

import anthropic
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import llm
from app.config import settings
from app.models import PlanEntry, Recipe
from app.nutrition import get_profile
from app.usage import plan_stats, preference_score

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
LIGHT = re.compile(r"soep|salade|smoothie|ontbijt|tosti|dessert|taart|koek")
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


def display_name(name: str) -> str:
    """'AH gesneden verspakket \'Indonesische\' nasi goreng' -> 'Indonesische nasi goreng' (label toont 'Maaltijdpakket')."""
    short = re.sub(r"^ah\s+(excellent\s+|biologisch\s+)?(gesneden\s+)?verspakket\s+", "", name, flags=re.I)
    short = re.sub(r"(^|\s)['\"]([^'\"]+)['\"]", r"\1\2", short).strip()  # 'Indonesische' -> Indonesische
    return (short[:1].upper() + short[1:]) if short else name


PROTEIN_WORDS = {"vis": ("vis", "zalm", "kabeljauw", "garnal", "tonijn", "heek", "makreel", "scampi", "ansjovis"),
                 "kip": ("kip", "chicken", "kalkoen"),
                 "vlees": ("gehakt", "rund", "beef", "varken", "spek", "worst", "chorizo", "lam", "biefstuk", "ham"),
                 "vega": ("vega", "tofu", "halloumi", "linzen", "kikkererwt", "bonen", "falafel", "paneer", "ei ")}
CUISINE_WORDS = {"aziatisch": ("japans", "chinees", "thais", "teriyaki", "noedel", "bami", "nasi", "yakisoba", "wok",
                               "gado", "sate", "satay", "pad thai", "ramen", "korma", "indonesisch", "oosters"),
                 "indiaas": ("indiaas", "curry", "tikka", "masala", "tandoori", "madras", "butter chicken", "dahl"),
                 "italiaans": ("italiaans", "pasta", "lasagne", "spaghetti", "risotto", "pizza", "gnocchi", "pesto"),
                 "mexicaans": ("mexicaans", "taco", "burrito", "enchilada", "nacho", "tortilla", "chili con", "fajita"),
                 "midden-oosters": ("shoarma", "gyros", "pita", "shakshuka", "falafel", "couscous", "baharat", "grieks"),
                 "hollands": ("stamppot", "zuurkool", "hutspot", "boerenkool", "erwtensoep", "draadjesvlees")}


def guessed_profile(recipe: Recipe) -> dict:
    """Zonder gezondheidsprofiel: basis, eiwit en keuken raden uit de naam, zodat variatie toch werkt."""
    low = f" {recipe.name.lower()} "
    out: dict = {}
    for chip in ("rijst", "pasta", "aardappel", "wraps", "noedels"):
        if chip in low or any(w in low for w in CHIPS[chip]["words"]):
            out["basis"] = chip
            break
    else:
        if "soep" in low:
            out["basis"] = "soep"
    for eiwit, words in PROTEIN_WORDS.items():
        if any(w in low for w in words):
            out["eiwit"] = eiwit
            break
    for keuken, words in CUISINE_WORDS.items():
        if any(w in low for w in words):
            out["keuken"] = keuken
            break
    return out


def dish_key(name: str) -> str:
    """Zelfde gerecht, ander recept ('AH verspakket gado gado' en 'AH gesneden verspakket gado gado')."""
    return re.sub(r"[^a-z0-9]+", " ", display_name(name).lower()).strip()


def _variety_penalty(profile: dict | None, chosen: list[dict]) -> float:
    if not profile:
        return 0.0
    same = lambda key: sum(1 for p in chosen if p and p.get(key) and p.get(key) == profile.get(key))
    return 10 * same("basis") + 8 * same("eiwit") + 5 * same("keuken")


def _health(profile: dict | None) -> float:
    if not profile:
        return 25.0  # neutraal: recept zonder profiel valt niet weg
    return profile["score"] * 8 + min(profile["groente_g"], 250) / 12 - abs(profile["kcal"] - 600) / 30


def propose(db: Session, monday: date, wishes: dict[str, str], per_day: int = 3,
            today: date | None = None, replace: set[str] | None = None) -> list[dict]:
    """wishes: {"2026-10-12": "rijst", ...}. Geeft per dag {date, wish, kind, options} (niets opgeslagen)."""
    today = today or date.today()
    stats = plan_stats(db)
    taken = {e.date: e for e in db.execute(select(PlanEntry).where(
        PlanEntry.date >= str(monday), PlanEntry.date <= str(monday + timedelta(days=6)))).scalars()
        if e.date not in (replace or set())}  # "Wijzig": die dag telt als open
    recipes = db.execute(select(Recipe).where(Recipe.archived.is_(False))).scalars().all()
    profiles = {r.id: get_profile(db, r.id) for r in recipes}
    week_ids = {e.recipe_id for e in taken.values() if e.kind == "recipe"}
    by_id = {r.id: r for r in recipes}
    chosen_profiles = [profiles.get(rid) or (guessed_profile(by_id[rid]) if rid in by_id else {}) for rid in week_ids]
    used: set[int] = set(week_ids)
    used_dishes = {dish_key(by_id[rid].name) for rid in week_ids if rid in by_id}
    favorites_chosen = sum(1 for rid in week_ids if rid in by_id and by_id[rid].favorite)
    prev_cuisine: str | None = None
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
        free = lambda r: r.id not in used and dish_key(r.name) not in used_dishes
        if wish == "vrij":  # "geen idee" = een volwaardige avondmaaltijd, geen soep of salade
            pool = [r for r in recipes if free(r) and not LIGHT.search(r.name.lower())
                    and not re.search(r"tapas|hapje|borrel|gilda|bruschetta", r.name.lower())]
        else:
            pool = [r for r in recipes if free(r) and matches(r, profiles[r.id], wish)]
        name_words = CHIPS.get(wish, {}).get("words", ()) + ((wish,) if wish in CHIPS else ())
        scored = []
        for r in pool:
            p = profiles[r.id] or guessed_profile(r)
            s = preference_score(r, stats.get(r.id), today) + _health(profiles[r.id]) - _variety_penalty(p, chosen_profiles)
            if name_words and any(w.strip() and w.strip() in r.name.lower() for w in name_words):
                s += 15  # wens staat in de naam ("nasi", "rijst"): beter dan alleen een ingrediënt
            if r.favorite and favorites_chosen >= 2:
                s -= 30  # hooguit twee favorieten per week, anders steeds hetzelfde
            if prev_cuisine and p.get("keuken") == prev_cuisine and prev_cuisine != "overig":
                s -= 15  # niet twee avonden achter elkaar dezelfde keuken
            quick = (minutes(r.total_time) or 99) <= 30
            tiebreak = hashlib.md5(f"{monday}-{r.id}".encode()).hexdigest()  # per week anders, niet alfabetisch
            scored.append((s, not quick, tiebreak, r))
        scored.sort(key=lambda x: (-x[0], x[1], x[2]))
        item["kind"] = "recipe" if scored else "none"
        options, seen_dish = [], set()
        for *_, r in scored:  # alternatieven: geen twee keer hetzelfde gerecht
            if dish_key(r.name) in seen_dish:
                continue
            seen_dish.add(dish_key(r.name))
            p = profiles[r.id] or guessed_profile(r)
            options.append({"recipe_id": r.id, "name": display_name(r.name), "image_url": r.image_url,
                            "total_time": r.total_time, "favorite": bool(r.favorite),
                            "pack": r.collection == "maaltijdpakket", "eiwit": p.get("eiwit", ""),
                            "keuken": p.get("keuken", ""), "basis": p.get("basis", "")})
            if len(options) == per_day:
                break
        item["options"] = options
        if scored:
            top = scored[0][-1]
            used.add(top.id)
            used_dishes.add(dish_key(top.name))
            favorites_chosen += bool(top.favorite)
            tp = profiles[top.id] or guessed_profile(top)
            chosen_profiles.append(tp)
            prev_cuisine = tp.get("keuken")
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
