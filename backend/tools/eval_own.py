"""Vaste gevallen uit de review van onze eigen recepten (tests/data/own_cases.json).

    python -m tools.eval_own          # offline met zoekcache
    python -m tools.eval_own --live   # vernieuwt tests/data/own_search_cache.json

Per geval: welke woorden het gekozen product moet/mag niet bevatten, of er juist niets gekozen mag worden
("none": keukengerei, voorraad, onleesbare regel) en eventueel het aantal verpakkingen.
"""

import argparse
import asyncio
import json
import sys
import unicodedata
from pathlib import Path

from app.api import routes

DATA = Path(__file__).resolve().parent.parent / "tests" / "data"
CASES = DATA / "own_cases.json"
CACHE = DATA / "own_search_cache.json"


def _norm(s: str) -> str:
    return unicodedata.normalize("NFKD", s.lower()).encode("ascii", "ignore").decode()


def check(case: dict, ing: dict) -> str | None:
    name = (ing.get("product") or {}).get("name") or ""
    n = _norm(name)
    if case.get("none"):
        return None if not name else f"had niets moeten kiezen, koos {name}"
    if not name:
        return "geen product" if case.get("include") else None
    if case.get("include") and not any(_norm(w) in n for w in case["include"]):
        return f"{name} bevat geen van {case['include']}"
    bad = [w for w in case.get("exclude", []) if _norm(w) in n]
    if bad:
        return f"{name} bevat {bad}"
    if case.get("qty") and ing.get("quantity") != case["qty"]:
        return f"aantal {ing.get('quantity')} i.p.v. {case['qty']} ({name})"
    return None


async def run(live: bool, save: bool = True) -> dict:
    cases = json.loads(CASES.read_text())
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    real = routes.ah_client.search_products

    async def search(query: str, size: int = 20):
        key = query.lower()
        if live or key not in cache:
            cache[key] = await real(query, size=size)
            for p in cache[key]:
                p.pop("image_url", None)
        return [dict(p) for p in cache[key]]

    routes.ah_client.search_products = search
    try:
        ings = [{"text": c["text"], "search": c["text"], "skip": False, "quantity": 1, "product": None} for c in cases]
        await routes._automatch(ings)
    finally:
        routes.ah_client.search_products = real
        if save:
            CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1, sort_keys=True))
    fails = [(c["text"], err) for c, i in zip(cases, ings) if (err := check(c, i))]
    return {"total": len(cases), "ok": len(cases) - len(fails), "fails": fails}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", action="store_true")
    args = ap.parse_args()
    r = asyncio.run(run(args.live))
    print(f"{r['ok']}/{r['total']} goed")
    for text, err in r["fails"]:
        print(f"  ✗ {text[:45]:47} {err}")


if __name__ == "__main__":
    sys.exit(main())
