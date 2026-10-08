"""Koppel receptingrediënten aan AH-producten.

Voorkeuren (Gerd-Jan): biologisch waar mogelijk, anders AH-huismerk; hoeveelheden slim omrekenen naar
verpakkingen; basisingrediënten (zout, peper, olie, water, ...) overslaan.
"""

import math
import re
from fractions import Fraction

from app.clients.mealie import clean_search

MATCH_VERSION = 3

# Basisspullen die je meestal in huis hebt: niet automatisch op de lijst
PANTRY = {
    "zout", "peper", "zwarte peper", "witte peper", "zeezout", "zeezoutvlokken", "grof zeezout", "water",
    "kraanwater", "kokend water", "ijswater", "olie", "olijfolie", "extra vierge olijfolie",
    "extra vergine olijfolie", "zonnebloemolie", "bakolie", "boter om in te bakken", "suiker",
    "peper en zout", "zout en peper", "zeezoutvlokken en zwarte peper",
}

# Categorieën die nooit een ingrediënt zijn (snoep, drogisterij, bakmixen, ...)
BAD_CATEGORIES = {
    "koek, snoep, chocolade", "snoep", "drogisterij", "huishouden", "baby en kind", "huisdier",
    "diepvries snacks", "bier en aperitieven", "wijn en bubbels", "frisdrank en sappen",
}
BAD_WORDS = {"bakmix", "kauwgom", "pastilles", "drop", "shampoo", "zeep", "parfum", "suikervrij"}

_UNIT_ALIASES = {
    "g": "g", "gr": "g", "gram": "g", "kg": "kg", "ml": "ml", "cl": "cl", "dl": "dl", "l": "l",
    "el": "el", "eetlepel": "el", "eetlepels": "el", "tl": "tl", "theelepel": "tl", "theelepels": "tl",
    "stuk": "stuk", "stuks": "stuk", "st": "stuk", "teen": "stuk", "tenen": "stuk", "teentje": "stuk",
    "teentjes": "stuk", "blik": "stuk", "blikje": "stuk", "blikjes": "stuk", "pot": "stuk", "potje": "stuk",
    "zakje": "stuk", "zak": "stuk", "pak": "stuk", "bosje": "bos", "bos": "bos", "bosjes": "bos",
    "takje": "takje", "takjes": "takje", "plak": "stuk", "plakje": "stuk", "plakjes": "stuk",
}
_TO_BASE = {"kg": ("g", 1000), "g": ("g", 1), "l": ("ml", 1000), "dl": ("ml", 100), "cl": ("ml", 10),
            "ml": ("ml", 1), "el": ("ml", 15), "tl": ("ml", 5)}
_FRACTIONS = {"½": "1/2", "¼": "1/4", "¾": "3/4", "⅓": "1/3", "⅔": "2/3"}
_AMOUNT_RE = re.compile(
    r"(?P<n>\d+(?:[.,]\d+)?(?:\s*[/]\s*\d+)?|[½¼¾⅓⅔])\s*(?P<n2>[½¼¾⅓⅔])?\s*(?P<u>[a-zA-Z]+)?", re.IGNORECASE
)


def _to_number(raw: str) -> float:
    raw = _FRACTIONS.get(raw, raw).replace(",", ".").replace(" ", "")
    return float(Fraction(raw)) if "/" in raw else float(raw)


def parse_amount(text: str) -> tuple[float, str] | None:
    """Pak de hoeveelheid uit een regel ("250 g quinoa", "Halloumi 75 g", "½ bosje munt")."""
    for m in _AMOUNT_RE.finditer(text):
        try:
            amount = _to_number(m.group("n"))
            if m.group("n2"):
                amount += _to_number(m.group("n2"))
        except (ValueError, ZeroDivisionError):
            continue
        unit = _UNIT_ALIASES.get((m.group("u") or "").lower(), "")
        if unit or m.start() == 0:
            return amount, unit or "stuk"
    return None


def needed(text: str) -> dict | None:
    """Hoeveelheid in basis-eenheid: {"amount": 250, "unit": "g"|"ml"|"stuk"|"bos"}."""
    parsed = parse_amount(text)
    if not parsed:
        return None
    amount, unit = parsed
    if unit in _TO_BASE:
        base, factor = _TO_BASE[unit]
        return {"amount": amount * factor, "unit": base, "spoon": unit in ("el", "tl")}
    return {"amount": amount, "unit": unit, "spoon": False}


def pack_size(unit_size: str) -> dict | None:
    """AH `salesUnitSize` ("225 g", "1 kg", "500 ml", "3 stuks", "per stuk", "bos") naar basis-eenheid."""
    s = (unit_size or "").lower().replace(",", ".")
    if "per stuk" in s or s.strip() in ("stuk", "1 stuk"):
        return {"amount": 1, "unit": "stuk"}
    m = re.search(r"(\d+(?:\.\d+)?)\s*(kg|g|ml|cl|dl|l|stuks?|st)\b", s)
    if not m:
        return {"amount": 1, "unit": "bos"} if "bos" in s else None
    n, u = float(m.group(1)), m.group(2)
    if u in _TO_BASE:
        base, factor = _TO_BASE[u]
        return {"amount": n * factor, "unit": base}
    return {"amount": n, "unit": "stuk"}


def packs_for(need: dict | None, pack: dict | None) -> int | None:
    """Aantal verpakkingen, of None als de eenheden niet vergelijkbaar zijn."""
    if not need or not pack or need["unit"] != pack["unit"] or not pack["amount"]:
        return None
    return max(1, math.ceil(need["amount"] / pack["amount"] - 1e-9))


def is_pantry(search: str, text: str = "") -> bool:
    term = clean_search(search or text).lower().strip()
    return term in PANTRY or any(term == p for p in PANTRY)


def _tokens(s: str) -> list[str]:
    return [t for t in re.split(r"[^a-zà-ÿ0-9]+", s.lower()) if len(t) > 1]


def _stem(t: str) -> str:
    for suf in ("en", "s", "e"):
        if t.endswith(suf) and len(t) - len(suf) >= 4:
            return t[: -len(suf)]
    return t


def score(product: dict, query: str) -> float:
    """Hoger = beter. Negatief = niet gebruiken."""
    title = (product.get("name") or "").lower()
    category = (product.get("category") or "").lower()
    if category in BAD_CATEGORIES or any(w in title for w in BAD_WORDS):
        return -100
    if product.get("available") is False:
        return -100
    q = [_stem(t) for t in _tokens(query) if t not in {"en", "of", "de", "het", "een", "van", "met"}]
    t_tokens = [_stem(t) for t in _tokens(title)]
    if q and not all(any(qt in tt or tt in qt for tt in t_tokens) for qt in q):
        return -50  # niet alle zoekwoorden terug te vinden in de titel
    extra = max(0, len(t_tokens) - len(q) - 2)
    brand = (product.get("brand") or "").lower()
    organic = "biologisch" in title or product.get("organic")
    huismerk = brand == "ah" or title.startswith("ah ")
    s = 50 - extra * 4
    if organic:
        s += 25
    if huismerk:
        s += 15
    if q and t_tokens[-1:] and q[-1] in t_tokens[-1]:
        s += 5  # kernwoord staat achteraan ("AH Rode uien")
    return s


def choose(products: list[dict], query: str) -> dict | None:
    ranked = sorted(((score(p, query), i, p) for i, p in enumerate(products)), key=lambda x: (-x[0], x[1]))
    if ranked and ranked[0][0] > 0:
        return ranked[0][2]
    return None
