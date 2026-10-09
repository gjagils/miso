"""Gezondheids- en variatieprofiel per recept (schatting door Claude) en weekanalyse.

Schattingen zijn grof (±20%): de app toont ze als richting, niet als harde getallen.
Richtlijnen (Voedingscentrum, Schijf van Vijf): 250 g groente per dag (avondeten ~150-200 g),
1x per week vis, wissel vlees af met vega/peulvruchten, varieer zetmeelbasis.
"""

import json
import re
from datetime import date, timedelta

import anthropic
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.clients.extractor import _parse_json
from app.config import settings
from app.logging_config import logger
from app.models import PlanEntry, Recipe, RecipeProfile

PROFILE_VERSION = 1
PROTEINS = ("vis", "vlees", "kip", "vega", "vegan", "peulvruchten", "ei", "zuivel")
BASES = ("pasta", "rijst", "aardappel", "brood", "noedels", "granen", "wraps", "geen", "overig")
CUISINES = ("hollands", "italiaans", "mediterraan", "aziatisch", "indiaas", "mexicaans", "midden-oosters", "overig")

PROFILE_PROMPT = f"""Je bent diëtist en beoordeelt avondmaaltijden voor een Nederlands gezin.
Je krijgt een recept (naam, aantal personen, ingrediënten). Schat per persoon en antwoord ALLEEN met valid JSON:
{{
  "kcal": 550,                      // kcal per persoon (geheel getal)
  "groente_g": 200,                 // gram groente (incl. peulvruchten-groente, excl. aardappel) per persoon
  "eiwit": "vis",                   // hoofd-eiwitbron, één van: {", ".join(PROTEINS)}
  "basis": "pasta",                 // zetmeelbasis, één van: {", ".join(BASES)}
  "keuken": "italiaans",            // één van: {", ".join(CUISINES)}
  "volkoren": false,                // is de zetmeelbasis volkoren/peulvrucht?
  "schijf": {{"groente_fruit": true, "zetmeel": true, "eiwit": true, "zuivel": false, "vetten": true}},
  "score": 4,                       // 1-5: hoe goed past dit in de Schijf van Vijf
  "toelichting": "max 1 zin"
}}
Regels: gebruik het aantal personen uit het recept (anders 4). Bewerkte vleeswaren/kant-en-klaar = lagere score.
Wees realistisch, liever iets te hoog dan te laag met kcal."""


def _clean(raw: dict) -> dict:
    """Valideer en begrens wat het model teruggeeft."""
    def pick(value, allowed, default):
        v = str(value or "").lower().strip()
        return v if v in allowed else default

    schijf = raw.get("schijf") if isinstance(raw.get("schijf"), dict) else {}
    return {
        "kcal": max(100, min(2000, int(float(raw.get("kcal") or 0) or 600))),
        "groente_g": max(0, min(1000, int(float(raw.get("groente_g") or 0)))),
        "eiwit": pick(raw.get("eiwit"), PROTEINS, "vlees"),
        "basis": pick(raw.get("basis"), BASES, "overig"),
        "keuken": pick(raw.get("keuken"), CUISINES, "overig"),
        "volkoren": bool(raw.get("volkoren")),
        "schijf": {k: bool(schijf.get(k)) for k in ("groente_fruit", "zetmeel", "eiwit", "zuivel", "vetten")},
        "score": max(1, min(5, int(float(raw.get("score") or 3)))),
        "toelichting": str(raw.get("toelichting") or "")[:200],
    }


async def estimate_profile(recipe: Recipe) -> dict:
    if not settings.anthropic_api_key:
        raise ValueError("ANTHROPIC_API_KEY is niet ingesteld.")
    lines = "\n".join(f"- {i.get('text', '')}" for i in recipe.ingredients if i.get("text"))
    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
    message = await client.messages.create(
        model=settings.anthropic_model,
        max_tokens=2000,
        system=PROFILE_PROMPT,
        messages=[{"role": "user", "content": f"Recept: {recipe.name}\nPersonen: {recipe.servings or 'onbekend'}\n"
                                              f"Ingrediënten:\n{lines}"}],
    )
    if message.stop_reason == "refusal":
        raise ValueError("Claude kon dit recept niet beoordelen.")
    text = next((b.text for b in message.content if getattr(b, "type", "") == "text"), "")
    return _clean(_parse_json(text))


def get_profile(db: Session, recipe_id: int) -> dict | None:
    row = db.execute(select(RecipeProfile).where(RecipeProfile.recipe_id == recipe_id)).scalar_one_or_none()
    if not row or row.version != PROFILE_VERSION:
        return None
    return json.loads(row.profile_json)


def save_profile(db: Session, recipe_id: int, profile: dict) -> None:
    row = db.execute(select(RecipeProfile).where(RecipeProfile.recipe_id == recipe_id)).scalar_one_or_none()
    if row:
        row.profile_json, row.version = json.dumps(profile, ensure_ascii=False), PROFILE_VERSION
    else:
        db.add(RecipeProfile(recipe_id=recipe_id, profile_json=json.dumps(profile, ensure_ascii=False),
                             version=PROFILE_VERSION))
    db.commit()


async def ensure_profile(db: Session, recipe: Recipe) -> dict | None:
    profile = get_profile(db, recipe.id)
    if profile is None:
        try:
            profile = await estimate_profile(recipe)
            save_profile(db, recipe.id, profile)
        except Exception as e:  # noqa: BLE001 - de app moet zonder profiel blijven werken
            logger.warning("Profile for recipe %s failed: %s", recipe.id, e)
            return None
    return profile


# ── Weekanalyse ────────────────────────────────────────────────────────


def analyze_week(planned: list[tuple[str, dict | None]]) -> dict:
    """planned: [(datum, profiel)] voor geplande avondmaaltijden. Geeft totalen + signalen."""
    profs = [p for _, p in planned if p]
    n = len(profs)
    signals: list[dict] = []
    if not planned:
        return {"dagen": 0, "signalen": [], "gemiddeld_kcal": None, "groente_g_per_dag": None,
                "eiwit": {}, "basis": {}, "keuken": {}, "schijf_pct": None}
    count = lambda key: {v: sum(1 for p in profs if p[key] == v) for v in sorted({p[key] for p in profs})}
    eiwit, basis, keuken = count("eiwit"), count("basis"), count("keuken")
    avg_kcal = round(sum(p["kcal"] for p in profs) / n) if n else None
    veg = round(sum(p["groente_g"] for p in profs) / n) if n else None
    if n:
        if veg < 150:
            signals.append({"type": "let_op", "tekst": f"Gemiddeld {veg} g groente per avondeten; richtlijn is 150-200 g."})
        else:
            signals.append({"type": "goed", "tekst": f"Genoeg groente: gemiddeld {veg} g per avondeten."})
        if avg_kcal > 800:
            signals.append({"type": "let_op", "tekst": f"Vrij zwaar: gemiddeld {avg_kcal} kcal per persoon."})
        if n >= 4 and not eiwit.get("vis"):
            signals.append({"type": "tip", "tekst": "Nog geen vis deze week (advies: 1x per week)."})
        vega = eiwit.get("vega", 0) + eiwit.get("vegan", 0) + eiwit.get("peulvruchten", 0)
        if n >= 4 and vega < 2:
            signals.append({"type": "tip", "tekst": "Probeer 2 vegetarische avonden per week."})
        if eiwit.get("vlees", 0) + eiwit.get("kip", 0) > 4:
            signals.append({"type": "let_op", "tekst": "Veel vlees deze week."})
        for b, c in basis.items():
            if c >= 3 and b not in ("geen", "overig"):
                signals.append({"type": "let_op", "tekst": f"{c}x {b} deze week: wissel de basis af."})
        for k, c in keuken.items():
            if c >= 3 and k != "overig":
                signals.append({"type": "tip", "tekst": f"{c}x {k} deze week: misschien iets anders?"})
    schijf_pct = round(100 * sum(sum(p["schijf"].values()) for p in profs) / (5 * n)) if n else None
    return {"dagen": len(planned), "geprofileerd": n, "gemiddeld_kcal": avg_kcal, "groente_g_per_dag": veg,
            "eiwit": eiwit, "basis": basis, "keuken": keuken, "schijf_pct": schijf_pct, "signalen": signals}


def suggest_week(planned: list[dict], candidates: list[tuple[Recipe, dict]], empty_days: list[str],
                 recent_ids: set[int] | None = None) -> list[dict]:
    """Vul lege dagen met recepten die de week gevarieerd en gezond maken (greedy)."""
    chosen: list[dict] = []
    used = {p.get("recipe_id") for p in planned} | (recent_ids or set())
    profs = [p["profiel"] for p in planned if p.get("profiel")]
    for day in empty_days:
        best, best_score = None, -1e9
        for recipe, prof in candidates:
            if recipe.id in used:
                continue
            s = prof["score"] * 10 + min(prof["groente_g"], 250) / 10
            s -= abs(prof["kcal"] - 600) / 25  # rond 600 kcal per persoon
            same = lambda key: sum(1 for p in profs if p[key] == prof[key])
            s -= 12 * same("basis") + 10 * same("eiwit") + 6 * same("keuken")
            if prof["eiwit"] == "vis" and not any(p["eiwit"] == "vis" for p in profs):
                s += 15
            if prof["eiwit"] in ("vega", "vegan", "peulvruchten") and \
                    sum(p["eiwit"] in ("vega", "vegan", "peulvruchten") for p in profs) < 2:
                s += 10
            if s > best_score:
                best, best_score = (recipe, prof), s
        if not best:
            break
        recipe, prof = best
        used.add(recipe.id)
        profs.append(prof)
        chosen.append({"date": day, "recipe_id": recipe.id, "name": recipe.name, "profiel": prof})
    return chosen
