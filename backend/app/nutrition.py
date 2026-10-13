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
from app import llm
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
        model=await llm.model("snel"),  # korte JSON-taak: snel/goedkoop niveau
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


def analyze_week(planned: list[tuple[str, dict | None]], leftover_days: int = 0) -> dict:
    """planned: [(datum, profiel)] voor gekookte avondmaaltijden. Geeft totalen + signalen.

    Restjes (`leftover_days`) tellen als geplande avond, maar niet mee voor variatie (eiwit/basis/keuken):
    het is hetzelfde gerecht nog een keer. Voorraad-dagen ("hebben we al") tellen nergens mee."""
    profs = [p for _, p in planned if p]
    n = len(profs)
    signals: list[dict] = []
    if not planned:
        return {"dagen": leftover_days, "restjes": leftover_days, "signalen": [], "gemiddeld_kcal": None,
                "groente_g_per_dag": None, "eiwit": {}, "basis": {}, "keuken": {}, "schijf_pct": None}
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
    return {"dagen": len(planned) + leftover_days, "restjes": leftover_days, "geprofileerd": n, "gemiddeld_kcal": avg_kcal, "groente_g_per_dag": veg,
            "eiwit": eiwit, "basis": basis, "keuken": keuken, "schijf_pct": schijf_pct, "signalen": signals}


# Gewichten van de voorstelscore. Elke term is uitlegbaar; de uitleg per suggestie staat in `redenen`.
# Favorieten, 👍/👎 en vaak gekozen zitten in `prefs` (app/usage.py, uitlegbare optelsom, factor 0,6).
WEIGHTS = {
    "schijf": 10,        # score 1-5 van het profiel
    "groente": 0.1,      # per gram groente (tot 250 g)
    "kcal": 1 / 25,      # straf per kcal afstand tot 600
    "basis": 12, "eiwit": 10, "keuken": 6,  # straf per herhaling in de week
    "vis": 15, "vega": 10,                  # eerste vis; vega zolang er minder dan 2 zijn
    "voorkeur": 0.6,     # x usage.preference_score (favoriet, 👍/👎, vaak gekozen, recent gegeten)
    "bonus": 3,          # per euro besparing, tot 15
    "lang_niet": 1.5,    # per week sinds de laatste keer, tot 12
    "nooit": 6,          # nog nooit gekookt: ook eens proberen
    "kosten": 2,         # straf per euro per persoon boven 4 euro
    "wens": 10,          # per persoon die dit wenst, tot 20
}
VEGA = ("vega", "vegan", "peulvruchten")


def _ctx_terms(ctx: dict, today: date) -> tuple[float, list[str]]:
    """Score en redenen uit de context van één recept (fans, duimpjes, bonus, laatst gekookt, kosten, wensen)."""
    s, why = 0.0, []
    fans = ctx.get("fans") or []
    if fans:
        why.append(f"favoriet van {', '.join(fans[:3])}")
    up, down = ctx.get("thumbs_up") or 0, ctx.get("thumbs_down") or 0
    if down > up:
        why.append("vaker 👎 dan 👍")
    elif up and not fans:
        why.append("vonden jullie lekker")
    saving = ctx.get("bonus_saving") or 0
    if saving > 0:
        s += min(15, WEIGHTS["bonus"] * saving)
        why.append(f"in de bonus (−€{saving:.2f})".replace(".", ","))
    elif ctx.get("bonus_count"):
        s += 2
        why.append("in de bonus")
    last = ctx.get("last_cooked")
    if last:
        weeks = max(0, (today - date.fromisoformat(last)).days) / 7
        s += min(12, WEIGHTS["lang_niet"] * weeks)
        if weeks >= 3:
            why.append(f"{int(weeks)} weken niet gegeten")
    elif ctx.get("never_cooked", True):
        s += WEIGHTS["nooit"]
        why.append("nog nooit gekookt")
    cost = ctx.get("cost_pp")
    if cost is not None:
        s -= WEIGHTS["kosten"] * max(0.0, cost - 4)
        why.append(f"ongeveer €{cost:.2f}".replace(".", ",") + " p.p.")
    wishes = ctx.get("wishes") or []
    if wishes:
        s += min(20, WEIGHTS["wens"] * len(wishes))
        why.append(f"wens van {', '.join(wishes[:3])}")
    return s, why


def suggest_week(planned: list[dict], candidates: list[tuple[Recipe, dict]], empty_days: list[str],
                 recent_ids: set[int] | None = None, prefs: dict[int, float] | None = None,
                 context: dict[int, dict] | None = None, today: date | None = None) -> list[dict]:
    """Vul lege dagen met recepten die de week gevarieerd, gezond, lekker en voordelig maken (greedy).

    `prefs[recipe_id]`: usage.preference_score (favorieten, 👍/👎, vaak gekozen, recent gegeten).
    `context[recipe_id]` (optioneel): {"fans", "thumbs_up", "thumbs_down", "bonus_saving", "bonus_count",
    "last_cooked", "never_cooked", "cost_pp", "wishes"}. Elke suggestie krijgt `score`, `redenen` en `uitleg`."""
    today = today or date.today()
    context = context or {}
    chosen: list[dict] = []
    used = {p.get("recipe_id") for p in planned} | (recent_ids or set())
    profs = [p["profiel"] for p in planned if p.get("profiel")]
    for day in empty_days:
        best, best_score, best_why = None, -1e9, []
        for recipe, prof in candidates:
            if recipe.id in used:
                continue
            why = []
            s = prof["score"] * WEIGHTS["schijf"] + min(prof["groente_g"], 250) * WEIGHTS["groente"]
            s += WEIGHTS["voorkeur"] * (prefs or {}).get(recipe.id, 0)
            s -= abs(prof["kcal"] - 600) * WEIGHTS["kcal"]  # rond 600 kcal per persoon
            same = lambda key: sum(1 for p in profs if p[key] == prof[key])  # noqa: E731
            s -= WEIGHTS["basis"] * same("basis") + WEIGHTS["eiwit"] * same("eiwit") + WEIGHTS["keuken"] * same("keuken")
            if prof["eiwit"] == "vis" and not any(p["eiwit"] == "vis" for p in profs):
                s += WEIGHTS["vis"]
                why.append("vis deze week")
            if prof["eiwit"] in VEGA and sum(p["eiwit"] in VEGA for p in profs) < 2:
                s += WEIGHTS["vega"]
                why.append("vegetarisch")
            if prof["groente_g"] >= 200:
                why.append("veel groente")
            extra, extra_why = _ctx_terms(context.get(recipe.id) or {}, today) if recipe.id in context else (0.0, [])
            s += extra
            if s > best_score:
                best, best_score, best_why = (recipe, prof), s, why + extra_why
        if not best:
            break
        recipe, prof = best
        used.add(recipe.id)
        profs.append(prof)
        chosen.append({"date": day, "recipe_id": recipe.id, "name": recipe.name, "profiel": prof,
                       "score": round(best_score, 1), "redenen": best_why, "uitleg": ", ".join(best_why)})
    return chosen
