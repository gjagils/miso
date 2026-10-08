"""Koppel receptingrediënten aan AH-producten.

Voorkeuren (Gerd-Jan): biologisch waar mogelijk, anders AH-huismerk; hoeveelheden slim omrekenen naar
verpakkingen; basisingrediënten (zout, peper, olie, water, ...) overslaan.
"""

import math
import re
from fractions import Fraction

from app.clients.mealie import clean_search

MATCH_VERSION = 6

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
    r"(?P<n>\d+\s+\d+/\d+|\d+(?:[.,]\d+)?(?:\s*[/]\s*\d+)?|[½¼¾⅓⅔])\s*(?P<n2>[½¼¾⅓⅔])?\s*(?P<u>[a-zA-Z]+)?", re.IGNORECASE
)


def _to_number(raw: str) -> float:
    mixed = re.fullmatch(r"(\d+)\s+(\d+/\d+)", raw.strip())
    if mixed:  # "7 1/2" = 7,5
        return int(mixed.group(1)) + float(Fraction(mixed.group(2)))
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


EQUIPMENT = {
    "keukenrasp", "rasp", "koekenpan", "braadpan", "grillpan", "wokpan", "pan", "steelpan", "ovenschaal",
    "schaal", "bakplaat", "bakplaten", "kom", "vergiet", "zeef", "snijplank", "mes", "deksel", "staafmixer",
    "blender", "mixer", "bakvorm", "springvorm", "lepel", "garde", "spatel", "thermometer", "prikker",
    "satéprikkers", "cocktailprikkers", "keukenpapier", "aluminiumfolie", "bakpapier",
}


def is_equipment(search: str, text: str = "") -> bool:
    """Keukengerei staat soms tussen de ingrediënten ("grote koekenpan met deksel")."""
    words = set(_tokens(clean_search(search or text)))
    if not words:
        return False
    return bool(words & EQUIPMENT) and not words & {"pannenkoek", "pannenkoeken", "pandan", "panko", "pannenkoekenmix"}


def is_pantry(search: str, text: str = "") -> bool:
    term = clean_search(search or text).lower().strip()
    return term in PANTRY or any(term == p for p in PANTRY)


def _tokens(s: str) -> list[str]:
    return [t for t in re.split(r"[^a-zà-ÿ0-9]+", s.lower().replace("'", "")) if len(t) > 1]


def _stem(t: str) -> str:
    """Grof enkelvoud, consequent voor beide kanten: uien->ui, eieren->ei, tomaten/tomaat->tomat,
    sjalotten->sjalot, kampioentjes/kampioentje->kampioentj, pinda's->pinda, citroenen->citroen."""
    t = t.replace("'", "")
    for suf, keep in (("eren", 2), ("ien", 1), ("en", 3), ("s", 3)):
        if t.endswith(suf) and len(t) - len(suf) >= keep:
            t = t[: -len(suf)] + ("i" if suf == "ien" else "")
            break
    if t.endswith("e") and len(t) >= 5:
        t = t[:-1]
    t = re.sub(r"(aa|ee|oo|uu)", lambda m: m.group(0)[0], t)
    t = re.sub(r"([bcdfgklmnprstvz])\1$", r"\1", t)
    return t


# Woorden die iets over vorm/maat/verpakking zeggen, niet over wélk product: niet zoeken, niet eisen
DESCRIPTORS = {
    "middelgroot", "middelgrote", "groot", "grote", "klein", "kleine", "flink", "flinke", "rijp", "rijpe",
    "diepvries", "bevroren", "gedroogd", "gedroogde", "vers", "verse",
    "biologisch", "biologische", "bio", "in", "blik", "pot", "potje", "zak", "pak", "of", "en", "een", "van",
    "met", "de", "het", "voor", "naar", "smaak", "iets", "ongeveer", "ca", "stevig", "stevige", "handvol",
    "bevroren", "geraspt", "geraspte", "ah", "hele", "heel", "excellent",
    "afbakbroodje", "stijl",
}
# Vaste vertalingen van receptwoorden naar hoe AH het noemt
SYNONYMS = [
    (r"\b(kippen|kip)bouillon(blokjes?|tabletten|tablet)?\b", "bouillon kip"),
    (r"\b(runder|rund)bouillon(blokjes?|tabletten|tablet)?\b", "bouillon rund"),
    (r"\b(groente)bouillon(blokjes?|tabletten|tablet)?\b", "bouillon groente"),
    (r"\b(bos)?paddenstoelenbouillon(blokjes?|tabletten|tablet)?\b", "bouillon paddenstoel"),
    (r"\bbouillon(blokjes?|tabletten|tablet)\b", "bouillon"),
    (r"\bjasmijnrijst\b", "jasmijn rijst"),
    (r"\blasagnevel(len)?\b", "lasagne"),
    (r"\bscharrelei(eren)?\b", "eieren"),
    (r"\bei(eren)?\b", "eieren"),
    (r"\bspecerijenmelange\b", ""),
    (r"\bkruidenmix\b", ""),
]
# Merk-/variantwoorden in producttitels die niets over het product zelf zeggen
TITLE_NOISE = {"ah", "biologisch", "terra", "excellent", "basic", "scharrel", "plantaardig", "stuks", "stuk",
               "grootverpakking", "schaal", "verse", "vers", "per", "pack", "zacht", "romig", "ca", "en", "met",
               "iets", "hele", "heel", "gele", "witte", "extra", "vierge", "naturel", "losse", "middelgrote",
               "vrije", "uitloop", "kg", "gram", "ml", "deelblokjes", "grof", "fijn", "fijne", "world", "spice",
               "blend", "perfumed", "naturel"}
# Woorden die van een product iets anders maken dan het ingrediënt ("Peer siroop", "Curry madras verspakket")
OTHER_PRODUCT = {"siroop", "sap", "saus", "chips", "toast", "salami", "smaak", "snack", "snacks", "reep", "koek",
                 "taart", "cake", "mix", "spread", "drank", "thee", "verspakket", "maaltijd", "salade", "soep",
                 "pie", "roomkaas", "melba", "chocolade", "ijs", "dressing", "tapenade", "worst", "pizza",
                 "wrap", "burger", "kroket", "nuggets", "olijfmix", "woksmaakmaker", "kruidenmix", "marinade"}
# Rassen/soorten die AH als productnaam gebruikt zonder het woord zelf ("AH Conference schaal" = peren)
VARIETY = {"jasmin": "jasmijn", "jasmine": "jasmijn", "rice": "rijst", "conference": "peer", "doyenne": "peer", "elstar": "appel", "jonagold": "appel", "granny": "appel",
           "trostomaten": "tomaten", "cherrytomaten": "tomaten", "uitloopeieren": "eieren"}
# Losse woorden die je in de zoekterm kunt splitsen ("risottorijst" -> "risotto rijst")
HEADS = ("rijst", "cheese", "kaas", "saus", "brood", "olie", "azijn", "vlokken", "poeder", "bonen", "pasta",
         "noedels", "melk", "room", "boter")
HERBS = {"koriander", "peterselie", "dille", "basilicum", "munt", "bieslook", "tijm", "rozemarijn", "dragon",
         "salie", "kervel", "oregano", "citroengras", "gember"}


def query_terms(text: str) -> tuple[str, list[str], set[str]]:
    """Zoekterm voor AH, de woorden die in het product moeten zitten en vlaggen (fresh/dried/frozen)."""
    term = clean_search(text).lower()
    for pat, rep in SYNONYMS:
        term = re.sub(pat, rep, term)
    words = _tokens(term)
    flags = set()
    low = f" {text.lower()} "
    if " vers" in low:
        flags.add("fresh")
    if "gedroogd" in low:
        flags.add("dried")
    if "diepvries" in low:
        flags.add("frozen")
    if re.search(r"kruidenmix|specerij|gemalen|\bpoeder|\bzaad\b|zaadjes", low):
        flags.add("dried")
    for pct in re.findall(r"(\d+(?:[.,]\d+)?)\s*%", low):
        flags.add(f"pct:{pct.replace(',', '.')}")
    if re.search(r"\bbiologisch", low):
        flags.add("organic")
    keep = [w for w in words if w not in DESCRIPTORS and not w.isdigit()]
    if not keep:
        keep = words
    if keep and keep[-1] in HERBS and "dried" not in flags and not re.search(r"\b(tl|el|theelepel|eetlepel)\b", low):
        flags.add("fresh")  # "5 g koriander" = verse koriander; "1 tl koriander" = gedroogd
    return " ".join(keep), keep, flags


def _same(q: str, t: str) -> int:
    """2 = zelfde woord, 1 = samenstelling met dit woord als kern achteraan ("babyspinazie" bij "spinazie",
    of "scharrelkipfilet" bij "kipfilet"), 0 = niet."""
    qs, ts = _stem(q), _stem(t)
    if q == t or qs == ts or plural(q) == t or plural(t) == q or _stem(plural(q)) == ts:
        return 2
    if len(q) >= 3 and len(t) - len(q) >= 3 and (t.endswith(q) or ts.endswith(qs)):
        return 1
    if len(t) >= 4 and len(q) - len(t) >= 3 and (q.endswith(t) or qs.endswith(ts)):
        return 1
    return 0


def _concat_match(q: str, content: list[str]) -> list[int] | None:
    """'risottorijst' = 'risotto'+'rijst', 'cottagecheese' = 'cottage'+'cheese'."""
    for i in range(len(content)):
        for j in range(i + 2, min(len(content), i + 3) + 1):
            if _stem("".join(content[i:j])) == _stem(q):
                return list(range(i, j))
            if j - i == 2 and _stem(content[i + 1] + content[i]) == _stem(q):  # "orzo volkoren" = volkorenorzo
                return [i, i + 1]
    return None


def score(product: dict, query: str, flags: set[str] | None = None, need: dict | None = None) -> float:
    """Hoger = beter. Negatief = niet gebruiken."""
    flags = flags or set()
    title = (product.get("name") or "").lower()
    category = (product.get("category") or "").lower()
    if category in BAD_CATEGORIES or any(w in title for w in BAD_WORDS):
        return -100
    if product.get("available") is False:
        return -100
    q = [t for t in _tokens(query) if t not in DESCRIPTORS] or _tokens(query)
    qraw = set(_tokens(query))
    content = [VARIETY.get(t, t) for t in _tokens(title) if (t not in TITLE_NOISE or t in qraw) and not t.isdigit()]
    brand = (product.get("brand") or "").lower()
    for b in _tokens(brand):  # merknaam weg uit de inhoud ("Verstegen Komijnzaad" -> komijnzaad)
        if b in content and b not in q:
            content.remove(b)
    matched_t: set[int] = set()
    s = 60.0
    for qt in q:
        best = max(((_same(qt, t), i) for i, t in enumerate(content)), default=(0, -1))
        if best[0] < 2:
            parts = _concat_match(qt, content)  # eerst: aaneengeschreven ("risottorijst" = risotto + rijst)
            if parts is not None:
                matched_t.update(parts)
                continue
        if best[0] == 0:
            return -50  # zoekwoord niet in het product
        matched_t.add(best[1])
        s -= 0 if best[0] == 2 else 8
    extra = [t for i, t in enumerate(content) if i not in matched_t]
    s -= 7 * len(extra)
    qset = set(q)
    if any(t in OTHER_PRODUCT and t not in qset for t in extra):
        s -= 45  # ander soort product
    if " met " in f" {title} ":
        after = _tokens(title.split(" met ", 1)[1])
        if any(t not in qset and t not in TITLE_NOISE and not t.isdigit() for t in after):
            s -= 20  # "Peer met appel", "Rode bieten met ui": samengesteld product
    if content and 0 not in matched_t and extra and extra[0] == content[0]:
        s -= 45  # het product gaat over iets anders ("roomkaas met gember", "sap appel peer")
    if q and content and (q[-1] in content[-1] or _same(q[-1], content[-1])):
        s += 4
    organic = "biologisch" in title or product.get("organic")
    huismerk = brand.startswith("ah") or title.startswith("ah ")
    if organic:
        s += 6  # voorkeur bij verder gelijke producten, wint niet van een betere match
    if huismerk:
        s += 10
    if "fresh" in flags and category.startswith("soepen, sauzen, kruiden"):
        s -= 40  # verse kruiden, geen potje gedroogd
    if "dried" in flags and category.startswith("groente"):
        s -= 20
    if re.search(r"\b\d+-pack\b|\bmultipack\b", title) or re.match(r"^\s*\d+\s*x\s", product.get("unit_size") or ""):
        s -= 15  # meerdere verpakkingen in één: alleen als het echt nodig is
    if "frozen" in flags:
        s += 8 if category == "diepvries" else -30
    for f in flags:
        if f.startswith("pct:") and not re.search(rf"\b{re.escape(f[4:])}\s*%", title):
            s -= 40  # "Griekse yoghurt 10%" is niet de 2%-variant
    if "organic" in flags and not organic:
        s -= 20  # recept vraagt expliciet biologisch
    if "dried" in flags and category.startswith("soepen, sauzen, kruiden"):
        s += 6
    if "dried" in flags and re.search(r"\bpasta\b|\bpittig\b", title):
        s -= 15  # kruidenmix gevraagd, geen pasta
    if need and not need.get("spoon"):  # eetlepels zijn altijd een fractie van de fles
        pack = pack_size(product.get("unit_size", ""))
        packs = packs_for(need, pack)
        if packs:
            waste = (packs * pack["amount"] - need["amount"]) / max(need["amount"], 1e-9)
            s -= min(15.0, 6.0 * max(0.0, waste - 0.5))  # 250 g nodig -> geen grootverpakking
            s -= 4 * (packs - 1)  # liever 1 pak van 300 g dan 2 van 150 g
    return s


def choose(products: list[dict], query: str, flags: set[str] | None = None, need: dict | None = None) -> dict | None:
    ranked = sorted(((score(p, query, flags, need), i, p) for i, p in enumerate(products)), key=lambda x: (-x[0], x[1]))
    if ranked and ranked[0][0] >= 30:
        return ranked[0][2]
    return None


def plural(word: str) -> str:
    """Nederlands meervoud (genoeg voor AH-titels): ui->uien, citroen->citroenen, sjalot->sjalotten,
    peer->peren, kampioentje->kampioentjes, tomaat->tomaten."""
    w = word
    if w.endswith(("je", "ie")) or w.endswith(("a", "o", "u", "i")) and not w.endswith("ui"):
        return w + "s"
    if w.endswith("ui") or w.endswith("ei"):
        return w + "en"
    if w.endswith("e"):
        return w + "n"
    m = re.match(r"^(.*?)([aeiou])\2([^aeiou])$", w)
    if m:  # tomaat -> tomaten, peer -> peren
        return m.group(1) + m.group(2) + m.group(3) + "en"
    if len(w) > 6 and w.endswith(("on", "el", "er", "em", "en")):
        return w + "s"  # champignon -> champignons
    if re.search(r"[^aeiou][aeiou][bdfgklmnprst]$", w) and 3 < len(w) <= 6 and not w.endswith(("oen", "ier", "ien")):
        return w + w[-1] + "en"  # sjalot -> sjalotten
    return w + "en"


def _split_compound(word: str) -> str:
    for head in HEADS:
        if word.endswith(head) and len(word) - len(head) >= 3:
            return f"{word[: -len(head)]} {head}"
    return word


def search_queries(query: str) -> list[str]:
    """Meerdere zoekopdrachten: zoals het er staat, in meervoud, en biologisch (voorkeur)."""
    words = query.split()
    out = [query]
    split = " ".join(_split_compound(w) for w in words)
    if split != query:
        out.append(split)
    if words:
        pl = " ".join(words[:-1] + [plural(words[-1])])
        if pl != query:
            out.append(pl)
    out.append(f"biologisch {query}")
    return out
