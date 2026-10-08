"""Meet onze AH-koppeling tegen AH's eigen "Productsuggesties" (tests/data/ah_bar.txt).

    python -m tools.eval_bar            # gebruikt de zoekcache (offline, reproduceerbaar)
    python -m tools.eval_bar --live     # zoekt opnieuw bij AH en ververst de cache
    python -m tools.eval_bar --json out.json

Per ingrediënt: wat kiest AH, wat kiezen wij. "Gelijk" = zelfde product; "Zelfde soort" = zelfde
product maar andere variant (bv. biologisch, wat Gerd-Jan wil) of ander merk van hetzelfde.
"""

import argparse
import asyncio
import json
import re
import sys
from pathlib import Path

from app.api import routes
from app.matching import _stem, _tokens

DATA = Path(__file__).resolve().parent.parent / "tests" / "data"
BAR = DATA / "ah_bar.txt"
CACHE = DATA / "ah_bar_search_cache.json"

VARIANT_WORDS = {"ah", "biologisch", "terra", "excellent", "basic", "scharrel", "plantaardig", "stuks", "stuk",
                 "grootverpakking", "schaal", "verse", "vers", "de", "het", "en", "met", "van"}


def parse_bar() -> list[dict]:
    recipes, cur = [], None
    for line in BAR.read_text().splitlines():
        if line.startswith("# ") or not line.strip():
            continue
        if line.startswith("#"):
            title, _, pantry = line[1:].partition(" ~")
            cur = {"title": title.strip(), "pantry": [p for p in pantry.split(";") if p.strip()], "items": []}
            recipes.append(cur)
            continue
        ing, product, size, qty = line.split("|")
        cur["items"].append({"ingredient": ing, "product": product, "unit_size": size, "quantity": int(qty)})
    return recipes


def core(name: str) -> set[str]:
    """Kernwoorden van een productnaam, zonder merk/variant ("AH Biologisch Citroenen" -> {citroen})."""
    brandless = re.sub(r"^(de zaanse hoeve|de huisman|natuurfarm de boed|old mother|verstegen|euroma|unirice|"
                       r"biofan|kühne|fundo|souq|hak|marne|ah|de)\s+", "", name.lower())
    return {_stem(t) for t in _tokens(brandless) if t not in VARIANT_WORDS and not t.isdigit()}


# Woorden die een ander product van dezelfde soort aanduiden (prima vervanger)
SOFT = {_stem(w) for w in ("ongezouten", "ongebrande", "grof", "grove", "gemalen", "vloeibare", "mini", "fijne",
                            "naturel", "witte", "wit", "italiaanse", "japanse", "gesneden", "pittig", "zaanse",
                            "vet", "stijl", "gekookt", "iets", "kruimige", "deelblokjes", "creme", "crèmehoning",
                            "kastanjechampignons", "trostomaten", "platte", "franse", "limburgse", "zaanse",
                            "gemalen", "midden", "middelscherp", "limburgs", "vrije")}


def verdict(ours: str | None, theirs: str) -> str:
    """Streng: alleen 'zelfde soort' als het kernproduct gelijk is en verschillen alleen variant/maat zijn."""
    if not ours:
        return "geen"
    if ours.lower() == theirs.lower():
        return "gelijk"
    a, b = core(ours), core(theirs)
    if a == b:
        return "zelfde soort"
    extra = (a - b) | (b - a)
    if "".join(sorted(a, key=len, reverse=False)) in {"".join(b)} or "".join(a) in {"".join(sorted(b))} or \
            any("".join(p) == "".join(sorted(b)) for p in [sorted(a)]) or "".join(sorted(a)) == "".join(sorted(b)) or \
            {"".join(a)} & {"".join(b)} or (len(a) == 2 and "".join(sorted(a, key=lambda w: -len(w))) in b) or \
            (len(a) == 2 and any(x + y in b for x in a for y in a if x != y)) or \
            (len(b) == 2 and any(x + y in a for x in b for y in b if x != y)):
        return "zelfde soort"  # "soja saus" = "sojasaus"
    small = a if len(a) <= len(b) else b
    compound = any((x.endswith(y) or y.endswith(x)) and (min(len(x), len(y)) >= 4 or {y} == small or {x} == small)
                   for x in a for y in b)
    rest = {e for e in extra if not any((e.endswith(o) or o.endswith(e)) and min(len(e), len(o)) >= 4
                                        for o in (a | b) - {e})}
    if (a & b or compound) and all(e in SOFT or any(e.startswith(x) or x.startswith(e) for x in SOFT) for e in rest):
        return "zelfde soort"
    return "anders"


async def run(live: bool, save: bool = True) -> dict:
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    real_search = routes.ah_client.search_products

    async def search(query: str, size: int = 12):
        key = query.lower()
        if live or key not in cache:
            cache[key] = await real_search(query, size=size)
            for p in cache[key]:
                p.pop("image_url", None)
        return [dict(p) for p in cache[key]]

    routes.ah_client.search_products = search
    rows, totals = [], {"gelijk": 0, "zelfde soort": 0, "anders": 0, "geen": 0, "overgeslagen": 0}
    qty_ok = qty_n = 0
    try:
        for recipe in parse_bar():
            ings = [{"text": i["ingredient"], "search": i["ingredient"], "skip": False, "quantity": 1,
                     "product": None} for i in recipe["items"]]
            await routes._automatch(ings)
            for bar, ours in zip(recipe["items"], ings):
                name = (ours.get("product") or {}).get("name")
                v = "overgeslagen" if ours.get("auto_skip") else verdict(name, bar["product"])
                totals[v] += 1
                if v in ("gelijk", "zelfde soort"):
                    qty_n += 1
                    qty_ok += int(ours.get("quantity", 1) == bar["quantity"])
                rows.append({"recipe": recipe["title"], "ingredient": bar["ingredient"], "ah": bar["product"],
                             "ah_qty": bar["quantity"], "ours": name, "ours_qty": ours.get("quantity", 1),
                             "verdict": v})
    finally:
        routes.ah_client.search_products = real_search
        if save:
            CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1, sort_keys=True))
    n = len(rows)
    score = {
        "ingredienten": n,
        "gekoppeld_pct": round(100 * (totals["gelijk"] + totals["zelfde soort"] + totals["anders"]) / n, 1),
        "goed_pct": round(100 * (totals["gelijk"] + totals["zelfde soort"]) / n, 1),
        "gelijk_pct": round(100 * totals["gelijk"] / n, 1),
        "aantal_goed_pct": round(100 * qty_ok / qty_n, 1) if qty_n else 0.0,
        **totals,
    }
    return {"score": score, "rows": rows}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--json")
    args = ap.parse_args()
    result = asyncio.run(run(args.live))
    print(json.dumps(result["score"], ensure_ascii=False))
    for r in result["rows"]:
        if r["verdict"] not in ("gelijk",):
            print(f"  [{r['verdict']:12}] {r['ingredient'][:40]:42} AH: {r['ah'][:34]:36} wij: {(r['ours'] or '—')[:34]}"
                  f"  x{r['ours_qty']}/{r['ah_qty']}")
    if args.json:
        Path(args.json).write_text(json.dumps(result, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    sys.exit(main())
