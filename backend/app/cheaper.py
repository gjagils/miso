"""Goedkoper alternatief per gekoppeld product (B4).

Per ingrediënt zoeken we met dezelfde zoekopdrachten als het koppelen (`routes.search_candidates`) en houden
alleen producten over die volgens `matching.score` net zo goed bij het ingrediënt passen. Daarvan rekenen we de
kosten uit: prijs x aantal verpakkingen dat nodig is. Is dat minstens `MIN_SAVING` goedkoper dan het huidige
product, dan stellen we het voor. Miso verandert niets zelf; kiezen doet het gezin (en wordt dan een geleerde
voorkeur, zoals elke handmatige keuze).
"""

import asyncio

from app.ah_sync import _num
from app.matching import needed, pack_size, packs_for, score

MIN_SAVING = 0.20  # euro: kleiner is de moeite niet waard
MAX_INGREDIENTS = 14  # een recept heeft zelden meer koopbare regels; begrenst het aantal AH-calls


def _cost(price: float, need: dict | None, unit_size: str, fallback_packs: int) -> tuple[float, int]:
    packs = packs_for(need, pack_size(unit_size or "")) or fallback_packs
    return round(price * packs, 2), packs


def _product_view(p: dict) -> dict:
    return {k: p.get(k) for k in ("id", "name", "unit_size", "price", "image_url", "brand", "category", "available",
                                  "organic", "unit_price", "nix18")}


async def cheaper_for(recipe, search_candidates) -> list[dict]:
    """[{"index", "text", "manual", "current": {...}, "alternative": {...}, "saving"}], grootste besparing eerst.
    `search_candidates` is `routes.search_candidates` (meegegeven zodat tests AH kunnen vervangen)."""
    sem = asyncio.Semaphore(4)
    todo = [(i, ing) for i, ing in enumerate(recipe.ingredients)
            if not ing.get("skip") and not ing.get("auto_skip") and (ing.get("product") or {}).get("id")
            and _num((ing.get("product") or {}).get("price")) is not None][:MAX_INGREDIENTS]

    async def one(index: int, ing: dict) -> dict | None:
        text = ing.get("text", "")
        current = ing["product"]
        products, query, flags, need = await search_candidates(ing.get("search") or text, text, sem)
        if not query:
            return None
        base_packs = max(1, int(ing.get("quantity") or 1))
        cur_cost, cur_packs = _cost(_num(current["price"]), need, current.get("unit_size", ""), base_packs)
        best: dict | None = None
        for p in products:
            price = _num(p.get("price"))
            if (p.get("id") == current.get("id") or price is None or p.get("available") is False or p.get("nix18")):
                continue
            if max(score(p, query, flags, need, relaxed) for relaxed in (False, True)) < 30:
                continue  # past niet even goed bij het ingrediënt
            cost, packs = _cost(price, need, p.get("unit_size", ""), cur_packs)
            if cost <= cur_cost - MIN_SAVING and (best is None or cost < best["cost"]):
                best = {"product": _product_view(p), "cost": cost, "packs": packs}
        if not best:
            return None
        return {"index": index, "text": text, "manual": bool(ing.get("manual")),
                "current": {**_product_view(current), "cost": cur_cost, "packs": cur_packs},
                "alternative": {**best["product"], "cost": best["cost"], "packs": best["packs"]},
                "saving": round(cur_cost - best["cost"], 2)}

    found = [r for r in await asyncio.gather(*(one(i, ing) for i, ing in todo)) if r]
    found.sort(key=lambda r: -r["saving"])
    return found
