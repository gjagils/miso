"""Koppel receptingrediënten aan AH-producten.

Voorkeuren (Gerd-Jan): biologisch waar mogelijk, anders AH-huismerk; hoeveelheden slim omrekenen naar
verpakkingen; basisingrediënten (zout, peper, olie, water, ...) overslaan.
"""

import math
import re
import unicodedata
from fractions import Fraction

from app.clients.mealie import clean_search

MATCH_VERSION = 11

# Basisspullen die je meestal in huis hebt: niet automatisch op de lijst
PANTRY = {
    "zout", "peper", "zwarte peper", "witte peper", "zeezout", "zeezoutvlokken", "grof zeezout", "water",
    "kraanwater", "kokend water", "ijswater", "olie", "olijfolie", "extra vierge olijfolie",
    "extra vergine olijfolie", "zonnebloemolie", "bakolie", "boter om in te bakken", "suiker",
    "peper en zout", "zout en peper", "zeezoutvlokken en zwarte peper", "azijn",
}

# Categorieën die nooit een ingrediënt zijn (snoep, drogisterij, bakmixen, ...)
BAD_CATEGORIES = {
    "koek, snoep, chocolade", "snoep", "drogisterij", "huishouden", "baby en kind", "huisdier",
    "diepvries snacks", "bier en aperitieven", "wijn en bubbels", "frisdrank en sappen", "frisdrank, sappen, water",
    "koffie, thee", "gezondheid en sport", "koken, tafelen, vrije tijd",  # let op: noten staan bij "borrel"
}
# Verse groente en fruit: moeten uit de groente/fruit-afdeling komen (niet "Peer siroop", "Bieslook roomkaas")
PRODUCE = {
    "ui", "sjalot", "knoflook", "gember", "citroen", "limoen", "sinaasappel", "mandarijn", "appel", "peer", "banaan",
    "avocado", "tomaat", "komkommer", "paprika", "courgette", "aubergine", "wortel", "winterpeen", "peen",
    "pastinaak", "prei", "selderij", "bleekselderij", "knolselderij", "venkel", "broccoli", "bloemkool", "spinazie",
    "rucola", "sla", "veldsla", "ijsbergsla", "spitskool", "rodekool", "witlof", "boerenkool", "andijvie", "radijs",
    "biet", "pompoen", "champignon", "paddenstoel", "aardappel", "zoete aardappel", "mango", "ananas", "druif",
    "aardbei", "framboos", "bosui", "chilipeper", "peper", "lente-ui", "taugé", "snijboon", "sperzieboon",
    "peultje", "doperwt", "mais", "granaatappel", "kiwi", "meloen", "lollo",
}
OPTIONAL_WORDS = {"panko", "vers", "biologisch", "bio", "half", "heel", "mild", "jong", "oud", "belegen", "grof",
                  "fijn", "naturel", "gerookt", "gezouten", "ongezouten", "puur"}
SPICES = {"komijn", "kurkuma", "kaneel", "paprikapoeder", "nootmuskaat", "kardemom", "kruidnagel", "chilipoeder",
          "korianderzaad", "venkelzaad", "mosterdzaad", "oregano", "tijm", "laurier", "laurierblaadjes"}
BAD_WORDS = {"bakmix", "kauwgom", "pastilles", "drop", "shampoo", "zeep", "parfum", "suikervrij"}

_UNIT_ALIASES = {
    "g": "g", "gr": "g", "gram": "g", "kg": "kg", "ml": "ml", "cl": "cl", "dl": "dl", "l": "l",
    "el": "el", "eetlepel": "el", "eetlepels": "el", "tl": "tl", "theelepel": "tl", "theelepels": "tl",
    "stuk": "stuk", "stuks": "stuk", "st": "stuk", "teen": "teen", "tenen": "teen", "teentje": "teen",
    "teentjes": "teen", "stengel": "deel", "stengels": "deel", "blad": "deel", "blaadje": "deel", "blaadjes": "deel",
    "partje": "deel", "partjes": "deel", "schijf": "deel", "schijfje": "deel", "schijfjes": "deel", "reepje": "deel",
    "reepjes": "deel", "scheut": "deel", "scheutje": "deel", "klont": "deel", "klontje": "deel", "handvol": "deel",
    "handje": "deel", "snufje": "deel", "stukje": "deel", "stukjes": "deel", "blik": "stuk", "blikje": "stuk", "blikjes": "stuk", "pot": "stuk", "potje": "stuk",
    "zakje": "zakje", "zakjes": "zakje", "zak": "stuk", "pak": "stuk", "bosje": "bos", "bos": "bos", "bosjes": "bos",
    "takje": "deel", "takjes": "deel", "plak": "deel", "plakje": "deel", "plakjes": "deel",
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


PERSONS = 4  # het gezin kookt voor 4


def needed(text: str) -> dict | None:
    """Hoeveelheid in basis-eenheid: {"amount": 250, "unit": "g"|"ml"|"stuk"|"bos"}."""
    low = (text or "").lower()
    series = re.search(r"\((\d+(?:[.,]\d+)?)(?:\s*,\s*\d+(?:[.,]\d+)?){3,}\)", low)
    if series:  # HelloFresh "(1, 2, 3, 3, 4, 4)" = per aantal personen 1..6 -> neem 4 personen
        values = re.findall(r"\d+(?:[.,]\d+)?", series.group(0))
        amount = _to_number(values[min(PERSONS - 1, len(values) - 1)])
        return {"amount": amount, "unit": "stuk", "spoon": False}
    m = re.search(r"per persoon:?\s*([\d.,/½¼¾]+)\s*([a-z]+)?", low)
    parsed = parse_amount(f"{m.group(1)} {m.group(2) or ''}") if m else parse_amount(text)
    if not parsed:
        return None
    amount, unit = parsed
    if m:
        amount *= PERSONS  # "per persoon: 1 stuk" -> 4
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
    """Aantal verpakkingen, of None als de eenheden niet vergelijkbaar zijn.

    Tenen knoflook: een bol heeft ~8 tenen (~5 g per teen). Stengels/blaadjes/takjes zijn een deel van één
    product en tellen nooit als hele stuks ("4 stengels bleekselderij" = 1 bleekselderij)."""
    if need and pack and need["unit"] == "teen" and pack["amount"]:
        if pack["unit"] == "stuk":
            return max(1, math.ceil(math.ceil(need["amount"] / 8) / pack["amount"]))
        if pack["unit"] == "g":
            return max(1, math.ceil(need["amount"] * 5 / pack["amount"] - 1e-9))
    if need and need["unit"] == "stuk" and pack and pack["unit"] == "stuk" and need["amount"] > 10:
        return 1  # "30 stuks" is eerder een maat dan een aantal verpakkingen
    if not need or not pack or need["unit"] != pack["unit"] or not pack["amount"]:
        return None
    return max(1, math.ceil(need["amount"] / pack["amount"] - 1e-9))


EQUIPMENT = {
    "keukenrasp", "rasp", "koekenpan", "braadpan", "grillpan", "wokpan", "pan", "steelpan", "ovenschaal",
    "schaal", "bakplaat", "bakplaten", "kom", "vergiet", "zeef", "snijplank", "mes", "deksel", "staafmixer",
    "blender", "mixer", "bakvorm", "springvorm", "lepel", "garde", "spatel", "thermometer", "prikker",
    "satéprikkers", "cocktailprikkers", "keukenpapier", "aluminiumfolie", "bakpapier", "oven", "maatbeker", "wok",
    "dunschiller", "citruspers", "kookpan", "vijzel", "weegschaal", "keukenmachine", "foodprocessor", "aardappelstamper",
}


_CONTAINER_RE = re.compile(
    r"^\s*(\d+)\s*(x\b|blik|blikken|blikjes?|kuipjes?|zakken|bakjes?|pakjes?|pakken|pak|potjes?|potten|pot|"
    r"flesjes?|flessen|fles|bekers?|kuipen|doosjes?|dozen|netjes?|bollen|bol)\b", re.IGNORECASE)


def container_count(text: str) -> int | None:
    """'2 blikken tomaten', '2x garnalen', '3 kuipjes' -> 2/2/3 verpakkingen."""
    m = _CONTAINER_RE.match(text or "")
    if m and 0 < int(m.group(1)) <= 12:
        return int(m.group(1))
    n = needed(text or "")
    if n and n["unit"] == "stuk" and re.search(r"\bblik", (text or "").lower()):
        return max(1, math.ceil(n["amount"] - 1e-9))  # "per persoon: 0.5 blik" -> 2 blikken
    return None


def is_equipment(search: str, text: str = "") -> bool:
    """Keukengerei staat soms tussen de ingrediënten ("grote koekenpan met deksel")."""
    words = set(_tokens(clean_search(search or text)))
    if not words:
        return False
    if words & {"pannenkoek", "pannenkoeken", "pandan", "panko", "pannenkoekenmix", "pannenkoekmix"}:
        return False
    return bool(words & EQUIPMENT) or any(w.endswith(("pan", "pannen", "schaaf", "rasp", "schaal", "plank")) for w in words)


def has_no_product(text: str) -> bool:
    """Regels zonder zelfstandig naamwoord ("1 [ Plantaardige ]", "2 stukken")."""
    _, words, _ = query_terms(text)
    return not words or all(w.endswith(("ige", "ische", "isch")) for w in words)


PANTRY_WORDS = {"zout", "zeezout", "zeezoutvlokken", "peper", "zwarte", "witte", "versgemalen", "gemalen", "grof",
                "uit", "de", "molen", "en", "naar", "smaak", "water", "kraanwater", "olie"}
SPECIAL_OILS = {"sesamolie", "truffelolie", "chiliolie", "walnootolie", "kokosolie"}


def is_pantry(search: str, text: str = "") -> bool:
    term = clean_search(search or text).lower().strip()
    if term in PANTRY:
        return True
    term = query_terms(search or text)[0] or term
    if term in PANTRY:
        return True
    words = _tokens(term)
    if words and set(words) <= PANTRY_WORDS:
        return True  # "zeezout en zwarte peper uit de molen"
    # olie om in te bakken ("plantaardige olie", "neutrale olie", "arachideolie"); geen speciale olie
    if words and words[-1] in ("oil", "oils") and (set(words) & {"olive", "vegetable", "sunflower", "cooking"}
                                                   or len(words) == 1):
        return True  # "extra virgin olive oil" (maar niet "crispy chili in oil")
    return bool(words) and words[-1].endswith("olie") and words[-1] not in SPECIAL_OILS and len(words) <= 3


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
    "afbakbroodje", "stijl", "blikken", "blikjes", "blikje", "stengels", "stengel", "zakjes", "zakje", "pakje",
    "pakjes", "sneetjes", "sneetje", "bakjes", "bakje", "klont", "glas", "glazen", "bol", "bollen", "eetl", "theel",
    "tl", "el", "cm", "kuipje", "kuipjes", "uit", "molen", "desgewenst", "onbehandelde", "onbehandeld", "panklare",
    "erbij", "zelf", "toevoegen", "opt", "optioneel", "stukje", "stukjes", "blaadjes", "takjes", "snufje", "scheutje",
    "plakjes", "partjes", "teentjes", "tenen", "liter", "dl", "ml", "gram", "kg", "g", "stuk", "stuks", "per", "persoon",
    "stukken", "garnering", "garneren", "serveren", "liefst", "bijvoorbeeld", "bv", "evt", "eventueel", "naar", "keuze",
}
# Vaste vertalingen van receptwoorden naar hoe AH het noemt
SYNONYMS = [
    (r"\b(\w+)-\s+of\s+(\w+)", r"\2"),  # "runder- of groentebouillon" -> "groentebouillon"
    (r"\s+of\s+.*$", ""),  # alternatieven: neem de eerste ("bouillon of water")
    (r"\s+(en|&)\s+.*$", ""),  # "bieslook & dille", "rucola en veldsla" -> eerste
    (r"\s+met\s+.*$", ""),  # "kipfilet met tuinbrood" -> kipfilet
    (r"\b\d+x\b", ""),
    (r"\bbladpeterselie\b", "platte peterselie"),
    (r"\bbasilicumblad(eren)?\b", "basilicum"),
    (r"\bsalieblaadjes\b", "salie"),
    (r"\bknoflooktenen\b", "knoflook"),
    (r"\blaurierblaadjes\b|\blaunierblaadjes\b", "laurierblaadjes"),
    (r"\bgriekse grillkaas\b", "grillkaas"),
    (r"\b(kippen|kip)bouillon(blokjes?|tabletten|tablet|poeder)?\b", "bouillon kip"),
    (r"\b(runder|rund|rundvlees)bouillon(blokjes?|tabletten|tablet|poeder)?\b", "bouillon rund"),
    (r"\b(groente)bouillon(blokjes?|tabletten|tablet|poeder)?\b", "bouillon groente"),
    (r"\b(bos)?paddenstoelenbouillon(blokjes?|tabletten|tablet|poeder)?\b", "bouillon paddenstoel"),
    (r"\bbouillon(blokjes?|tabletten|tablet|poeder)\b", "bouillon"),
    (r"\bknoflookte(en|nen)\b", "knoflook"),
    (r"\bkorianderblad(eren)?\b", "koriander"),
    (r"\bcoriander\b", "koriander"),
    (r"\bsesam\b", "sesamzaad"),
    (r"\bpruimtomaat\b", "roma tomaten"),
    (r"\bcranberry'?s\b", "cranberries"),
    (r"\b(?!uitjes)(\w*[aeiou]t)jes\b", r"\1"),  # verkleinwoord: sjalotjes -> sjalot, tomaatjes -> tomaat
    (r"\bgrove\b", "grof"),
    (r"\btortilla'?s?\b", "tortilla wraps"),
    (r"\b50\s*-\s*50\s*burgers?\b|\bhalf-om-half burgers?\b", "half om half burgers"),
    (r"\bscharrel(\w{4,})\b", r"\1"),  # "scharrelkipfilet" -> kipfilet (variant, geen product)
    (r"^boter$", "roomboter"),
    (r"\bparmezaanse kaas\b|\bparmezaan\b", "parmigiano"),
    (r"\bscherpe mosterd\b", "dijon mosterd"),
    (r"\bjasmijnrijst\b", "jasmijn rijst"),
    (r"\blasagnevel(len)?\b", "lasagne"),
    (r"\bscharrelei(eren)?\b", "eieren"),
    (r"\bei(eren)?\b", "eieren"),
    (r"\bspecerijenmelange\b", "kruiden"),
    (r"\bkruidenmix\b", "kruiden"),
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
COMPOUND_OK = {"baby", "mini", "bio", "buffel", "kastanje", "cherry", "tros", "pruim", "roma", "jonge", "jong",
               "oude", "wilde", "half", "volle", "halfvolle", "magere", "rode", "witte", "gele", "groene", "zwarte",
               "platte", "krul", "room", "scharrel", "vrije", "uitloop", "verse", "vers", "griekse", "turkse", "italiaanse", "hollandse",
               "zeeuwse", "parel", "basmati", "zilvervlies", "volkoren", "spelt", "tarwe", "panklare", "gesneden",
               "grof", "fijn", "mais", "kikker", "bruine", "kidney", "ijsberg", "veld", "eikenblad", "boeren",
               "winter", "bos", "lente", "zoete", "zure", "slag", "kook", "kruimige", "vastkokende", "mozzarella",
               "kers", "trostomaat", "snoep", "romaine", "boterhammen", "pasta", "volle-", "tuin", "kaas", "hand",
               "pers", "tomaten", "jus"}
# Woordeinden die van een product iets anders maken ("tortilla wraps", "kaas biscuits", "tomaat tapenade")
OTHER_SUFFIX = ("wraps", "wrap", "biscuits", "biscuit", "tapenade", "sticks", "tussendoortje", "burritos", "burrito",
                "saus", "pilsener", "partymix", "noodles", "hummus", "dip", "dipsaus", "chips", "crackers", "koekjes",
                "drank", "sap", "siroop", "toast", "repen", "reep", "salade", "soep", "spread", "pasta-saus",
                "maaltijd", "verspakket", "pakket", "mix", "smaak", "sensatie", "kroketten", "snack", "azijn",
                "drink", "olijven", "olijf", "omelet", "spread", "smeerkaas", "dressing", "marinade")
# Kenmerken die in het product staan maar niet in het recept: verkeerd product
MARKED = ("gemarineerd", "glutenvrij", "geiten", "geit", "lactosevrij", "suikervrij", "light", "zero", "gevuld",
          "gepaneerd", "vegan", "vegetarisch", "knoflook", "kruiden", "pikant", "pittig", "truffel", "volkoren",
          "minder", "spaanse", "deelblokjes")
COLORS = {"rode", "rood", "groene", "groen", "gele", "geel", "witte", "wit", "zwarte", "zwart", "oranje", "paarse"}
CONFLICTS = [({"vastkokend", "vastkokende"}, {"kruimig", "kruimige"}), ({"kruimig", "kruimige"}, {"vastkokend", "vastkokende"}),
             ({"scherp", "scherpe"}, {"mild", "milde"}), ({"zoet", "zoete"}, {"pittig", "pittige", "scherp"})]
ALCOHOL = {"wijn", "bier", "brandy", "cognac", "port", "rum", "wodka", "whisky", "sherry", "likeur", "cider", "marsala",
           "prosecco", "cava", "jenever", "gin", "calvados", "amaretto", "grappa"}
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
    term = re.sub(r"\s*/.*$", "", term)  # HelloFresh: "250 g / 125 g"
    if ":" in term and term.split(":", 1)[1].strip():
        term = term.split(":", 1)[1]  # "verse kruidenmix: bieslook & dille" -> de kruiden zelf
    low_units = text.lower()
    if re.search(r"\b(tl|el|theel|eetl|theelepels?|eetlepels?)\b", low_units) and re.search(r"\bpaprika\b", term):
        term = re.sub(r"\bpaprika\b", "paprikapoeder", term)  # 1 tl paprika = poeder, niet de groente
    term = unicodedata.normalize("NFKD", term).encode("ascii", "ignore").decode() or term  # maïzena -> maizena
    for pat, rep in SYNONYMS:
        term = re.sub(pat, rep, term)
    term = re.sub(r"\b(?!\w+se\b)(\w+) kruiden\b", r"\1", term)  # "harissa kruiden" -> harissa, "italiaanse kruiden" blijft
    words = _tokens(term)
    flags = set()
    low = f" {text.lower()} "
    if " vers" in low:
        flags.add("fresh")
    if "gedroogd" in low:
        flags.add("dried")
    if "diepvries" in low:
        flags.add("frozen")
    if re.search(r"\bblik", low):
        flags.add("canned")
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


PARTICIPLES = {"fijngesneden", "gesneden", "geraspt", "geraspte", "gehakt", "gehakte", "gekookt", "gekookte",
               "geschild", "geschilde", "gepeld", "gepelde", "grofgesneden", "fijngehakt", "gemalen", "heel"}


def _head_index(q: list[str]) -> int:
    for i in range(len(q) - 1, -1, -1):
        if q[i] not in PARTICIPLES:
            return i
    return len(q) - 1


def _same(q: str, t: str) -> int:
    """2 = zelfde woord, 1 = samenstelling met dit woord als kern achteraan ("babyspinazie" bij "spinazie",
    of "scharrelkipfilet" bij "kipfilet"), 0 = niet."""
    qs, ts = _stem(q), _stem(t)
    if q == t or qs == ts or plural(q) == t or plural(t) == q or _stem(plural(q)) == ts:
        return 2
    if len(q) >= 3 and len(t) - len(q) >= 3 and (t.endswith(q) or ts.endswith(qs)):
        prefix = t[: len(t) - len(q)] if t.endswith(q) else ts[: len(ts) - len(qs)]
        # alleen onschuldige voorvoegsels: "roomboter"/"babyspinazie" ja, "knoflookboter"/"kokosmelk" nee
        return 1 if prefix.rstrip("-") in COMPOUND_OK else 0
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


def score(product: dict, query: str, flags: set[str] | None = None, need: dict | None = None,
          relaxed: bool = False) -> float:
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
            if qt != q[_head_index(q)] and len(q) > 1 and (relaxed or qt.endswith("e") or qt in OPTIONAL_WORDS
                                                             or qt in PARTICIPLES):
                s -= 12  # bijwoord ontbreekt (in de ruime zoekronde mag dat bij elk bijwoord) ("panko paneermeel" -> "Panko"): mag, maar kost punten
                continue
            return -50  # het kernwoord zit niet in het product
        matched_t.add(best[1])
        s -= 0 if best[0] == 2 else 14  # samenstelling: "kokosmelk" is niet "melk"
    extra = [t for i, t in enumerate(content) if i not in matched_t]
    s -= 7 * len(extra)
    qset = set(q)
    if any((t in OTHER_PRODUCT or t.endswith(OTHER_SUFFIX)) and t not in qset
           and not any(t.endswith(x) or x.endswith(t) for x in qset) for t in extra):
        s -= 45  # ander soort product
    title_tokens = set(_tokens(title))
    for m in MARKED:
        if any(t.startswith(m) or t.endswith(m) for t in title_tokens) and not any(m in x for x in qraw):
            s -= 35  # "gemarineerd", "glutenvrij", "geitenkaas", "knoflookboter"
            break
    qcol = {c[:4] for c in qraw & COLORS}
    tcol = {c[:4] for c in title_tokens & COLORS}
    if qcol and tcol and not qcol & tcol:
        s -= 40  # rode pesto is geen groene pesto
    for a, b in CONFLICTS:
        if qraw & a and title_tokens & b:
            s -= 40
    if product.get("nix18") and not (qraw & ALCOHOL or any(x.endswith(tuple(ALCOHOL)) for x in qraw)):
        s -= 60  # geen bier voor brandy/wijn-loze recepten
    if "canned" in flags and category.startswith(("groente", "fruit")):
        s -= 30  # "tomaten in blik" is geen verse tros
    if " met " in f" {title} ":
        after = _tokens(title.split(" met ", 1)[1])
        if any(t not in qset and t not in TITLE_NOISE and not t.isdigit() for t in after):
            s -= 20  # "Peer met appel", "Rode bieten met ui": samengesteld product
    nouns = [i for i, t in enumerate(content) if not (len(t) > 3 and t.endswith(("e", "se", "ge")) and t not in qset)]
    first_noun = nouns[0] if nouns else 0
    if content and first_noun not in matched_t and content[first_noun] in extra and len(content) > 1:
        s -= 60  # het product gaat over iets anders ("roomkaas met gember", "spinazie met boursin")
    if q and content and (q[-1] in content[-1] or _same(q[-1], content[-1])):
        s += 4
    organic = "biologisch" in title or product.get("organic")
    huismerk = brand.startswith("ah") or title.startswith("ah ")
    if organic:
        s += 6  # voorkeur bij verder gelijke producten, wint niet van een betere match
    if huismerk:
        s += 10
    else:
        s -= 12  # A-merk alleen als er geen AH-variant is
    head = _stem(q[_head_index(q)]) if q else ""
    if head in {_stem(w) for w in PRODUCE | HERBS} and not category.startswith(("groente", "fruit")):
        s -= 35  # verse groente/fruit/kruiden horen uit de groente-afdeling
    if head in {_stem(w) for w in SPICES} and not category.startswith(("soepen, sauzen, kruiden", "groente",
                                                                       "pasta, rijst, wereldkeuken")):
        s -= 40  # specerij, geen kaas met komijn
    if any(t.endswith("smaak") and t not in qset for t in extra):
        s -= 25  # "uienchutney truffelsmaak"
    if re.search(r"\bmild\b", title) and qset & {"scherpe", "scherp", "pittige", "pittig"}:
        s -= 30
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
    """Eerst streng (alle woorden moeten passen); vindt dat niets, dan ruim (bijwoorden mogen ontbreken)."""
    for relaxed in (False, True):
        ranked = sorted(((score(p, query, flags, need, relaxed), i, p) for i, p in enumerate(products)),
                        key=lambda x: (-x[0], x[1]))
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


def search_queries(query: str, flags: set[str] | None = None) -> list[str]:
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
    if words and _stem(words[-1]) != words[-1] and len(_stem(words[-1])) >= 4:
        out.append(" ".join(words[:-1] + [_stem(words[-1])]))  # "heekfilets" -> "heekfilet"
    if flags and "canned" in flags:
        out.append(f"{query} blik")  # "tomaten in blik" -> ook blikken zoeken
    out.append(f"biologisch {query}")
    return out
