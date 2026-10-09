"""AH-gegevens lezen: bonus, favorietenlijsten, Allerhande-favorieten, kassabonnen en online bestellingen.

Alleen lezen (plus het lijstje vullen via `AHClient.add_to_cart`). Hier staat bewust GEEN code die een
bestelling plaatst, afrekent, heropent of terugdraait.

Alle netwerkverkeer loopt via `_http` (tests vervangen die door fixtures). Fouten worden kort gelogd
(status + eerste 200 tekens van de body, nooit tokens) en als `AHDataError` doorgegeven.
Veldnamen worden met fallbacks gelezen: de API is onofficieel en verandert soms.
"""

import asyncio
import re
from datetime import date, datetime, timedelta
from urllib.parse import urlencode

import httpx

from app.clients.ah import AH_GRAPHQL_URL, DEFAULT_HEADERS, _user_call, ah_client
from app.logging_config import logger

API = "https://api.ah.nl"
BONUS_METADATA_URL = f"{API}/mobile-services/bonuspage/v3/metadata"
BONUS_SECTION_URL = f"{API}/mobile-services/bonuspage/v2/section"
BONUS_PERSONAL_URL = f"{API}/mobile-services/bonuspage/v1/personal"
LISTS_URL = f"{API}/mobile-services/lists/v3/lists"
ORDER_DETAILS_URL = f"{API}/mobile-services/order/v1/{{order_id}}/details-grouped-by-taxonomy"

# Zoals de iOS-app (en appie-go) zich bij GraphQL meldt.
CLIENT_HEADERS = {"x-client-name": "appie-ios", "x-client-version": "9.28", "Accept": "application/json"}


class AHDataError(Exception):
    """AH gaf geen bruikbaar antwoord. `str(e)` is een Nederlandse melding voor de gebruiker."""


# ── HTTP ───────────────────────────────────────────────────────────────


def _log_bad(what: str, resp: httpx.Response) -> None:
    body = (resp.text or "")[:200].replace("\n", " ")
    logger.warning("AH %s mislukt: HTTP %s | %s", what, resp.status_code, body)


async def _http(method: str, url: str, *, params: dict | None = None, body: dict | None = None,
                user: bool = True) -> httpx.Response:
    """Eén AH-call. `user=True`: met het token van de gebruiker (ververst automatisch), anders anoniem."""
    if params:
        url = f"{url}?{urlencode(params, doseq=True)}"
    if user:
        if not ah_client._user_token and not await ah_client._refresh_user_token():
            raise AHDataError("AH niet gekoppeld. Ga naar Instellingen.")
        return await _user_call(ah_client, method, url, body, extra_headers=CLIENT_HEADERS)
    async with httpx.AsyncClient(timeout=30) as client:
        for attempt in (1, 2):
            token = await ah_client._get_anonymous_token()
            headers = {**DEFAULT_HEADERS, **CLIENT_HEADERS, "Authorization": f"Bearer {token}"}
            resp = await client.request(method, url, headers=headers, json=body)
            if resp.status_code == 401 and attempt == 1:
                ah_client._anonymous_token = None
                continue
            return resp
    return resp


async def get_json(url: str, what: str, *, params: dict | None = None, user: bool = True):
    try:
        resp = await _http("GET", url, params=params, user=user)
    except AHDataError:
        raise
    except Exception as e:  # noqa: BLE001  (netwerk)
        logger.warning("AH %s mislukt: %s", what, type(e).__name__)
        raise AHDataError(f"AH was niet bereikbaar ({what}).") from e
    if resp.is_error:
        _log_bad(what, resp)
        raise AHDataError(f"AH gaf een fout bij {what} ({resp.status_code}).")
    try:
        return resp.json()
    except ValueError as e:
        _log_bad(what, resp)
        raise AHDataError(f"AH gaf een onleesbaar antwoord bij {what}.") from e


async def gql(query: str, variables: dict | None, what: str, *, user: bool = True) -> dict:
    """GraphQL op api.ah.nl/graphql. Geeft `data` terug; bij `errors` zonder data een AHDataError."""
    try:
        resp = await _http("POST", AH_GRAPHQL_URL, body={"query": query, "variables": variables or {}}, user=user)
    except AHDataError:
        raise
    except Exception as e:  # noqa: BLE001
        logger.warning("AH %s mislukt: %s", what, type(e).__name__)
        raise AHDataError(f"AH was niet bereikbaar ({what}).") from e
    if resp.is_error:
        _log_bad(what, resp)
        raise AHDataError(f"AH gaf een fout bij {what} ({resp.status_code}).")
    try:
        payload = resp.json()
    except ValueError as e:
        _log_bad(what, resp)
        raise AHDataError(f"AH gaf een onleesbaar antwoord bij {what}.") from e
    data = payload.get("data") if isinstance(payload, dict) else None
    if payload.get("errors") if isinstance(payload, dict) else False:
        msgs = "; ".join(str(e.get("message", ""))[:120] for e in payload["errors"] if isinstance(e, dict))
        logger.warning("AH %s: GraphQL-fouten: %s", what, msgs[:200])
        if not data:
            raise AHDataError(f"AH begreep de vraag niet ({what}).")
    if not isinstance(data, dict):
        _log_bad(what, resp)
        raise AHDataError(f"AH gaf geen gegevens terug ({what}).")
    return data


def _first(d: dict | None, *keys, default=None):
    """Eerste niet-lege waarde uit een rij mogelijke veldnamen."""
    if not isinstance(d, dict):
        return default
    for k in keys:
        v = d.get(k)
        if v not in (None, "", [], {}):
            return v
    return default


def _amount(v) -> float | None:
    """Prijs uit `1.99`, `"1.99"` of `{"amount": 1.99}`."""
    if isinstance(v, dict):
        v = v.get("amount")
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return f if f > 0 else None


def _int(v) -> int | None:
    try:
        i = int(v)
    except (TypeError, ValueError):
        return None
    return i if i > 0 else None


# ── 1. Bonus ───────────────────────────────────────────────────────────


def estimate_saving(mechanism: str, now: float | None, was: float | None) -> float | None:
    """Geschatte besparing per stuk. Eerst prijs-voor/na, anders afgeleid uit de actietekst."""
    if now and was and was > now:
        return round(was - now, 2)
    base = was or now
    if not base:
        return None
    m = (mechanism or "").lower()
    if pct := re.search(r"(\d{1,2})\s*%", m):
        return round(base * int(pct.group(1)) / 100, 2)
    if re.search(r"1\s*\+\s*1", m):
        return round(base / 2, 2)
    if g := re.search(r"(\d)\s*\+\s*(\d)", m):
        paid, free = int(g.group(1)), int(g.group(2))
        return round(base * free / (paid + free), 2)
    if "2e halve prijs" in m:
        return round(base / 4, 2)
    if "2e gratis" in m:
        return round(base / 2, 2)
    return None


def _bonus_product(p: dict, mechanism_fallback: str = "", segment: str = "") -> dict | None:
    pid = _int(_first(p, "webshopId", "id", "productId", "productNumber"))
    if not pid:
        return None
    price = p.get("priceV2") if isinstance(p.get("priceV2"), dict) else {}
    tiers = ((price.get("promotionLabel") or {}).get("tiers") or []) if price else []
    mech = _first(p, "bonusMechanism", "discountDescription") or (tiers[0].get("description") if tiers else "") \
        or mechanism_fallback or ""
    now = _amount(_first(p, "currentPrice")) or _amount(price.get("now"))
    was = _amount(_first(p, "priceBeforeBonus")) or _amount(price.get("was"))
    return {"id": pid, "title": _first(p, "title", "description", default="") or "", "mechanism": mech,
            "now": now, "was": was, "saving": estimate_saving(mech, now, was), "segment": segment}


def parse_bonus_section(section: dict) -> tuple[list[dict], list[dict]]:
    """(producten, groepen-zonder-producten) uit een bonuspage-sectie."""
    products, groups = [], []
    entries = _first(section, "bonusGroupOrProducts", "items", default=[]) or []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if isinstance(entry.get("product"), dict):
            if p := _bonus_product(entry["product"]):
                products.append(p)
        group = entry.get("bonusGroup")
        if isinstance(group, dict):
            mech = _first(group, "discountDescription", "bonusMechanism", default="") or ""
            seg = str(_first(group, "id", "segmentId", default="") or "")
            inner = [_bonus_product(p, mech, seg) for p in group.get("products") or [] if isinstance(p, dict)]
            inner = [p for p in inner if p]
            if inner:
                products.extend(inner)
            elif seg:
                groups.append({"id": seg, "title": _first(group, "segmentDescription", "title", default="") or "",
                               "mechanism": mech,
                               "saving": estimate_saving(mech, _amount(group.get("exampleForPrice")),
                                                         _amount(group.get("exampleFromPrice")))})
    return products, groups


def parse_bonus_metadata(meta: dict) -> dict:
    periods = _first(meta, "periods", default=[]) or []
    period = periods[0] if periods and isinstance(periods[0], dict) else {}
    cats: list[str] = []
    for tab in period.get("tabs") or []:
        for item in (tab or {}).get("urlMetadataList") or []:
            desc = _first(item, "description", "untranslatedDescription")
            if (item or {}).get("bonusType", "NATIONAL") == "NATIONAL" and desc and desc not in cats:
                cats.append(desc)
    return {"start": _first(period, "bonusStartDate", "startDate", default="") or "",
            "end": _first(period, "bonusEndDate", "endDate", default="") or "", "categories": cats}


BONUS_GROUP_QUERY = """query FetchBonusPromotionWithProducts($id: String, $periodStart: String, $periodEnd: String) {
  bonusPromotions(input: {id: $id, periodStart: $periodStart, periodEnd: $periodEnd,
                          filterUnavailableProducts: false, forcePromotionVisibility: true,
                          showAllPromotionSegments: true}) {
    id title
    products { id title priceV2 { now { amount } was { amount } promotionLabel { tiers { mechanism description } } } }
  }
}"""

MAX_GROUPS = 150


async def fetch_bonus(user: bool) -> dict:
    """Alle bonusproducten van de huidige periode, op webshopId. Persoonlijke bonus erbij als `user`."""
    meta = parse_bonus_metadata(await get_json(BONUS_METADATA_URL, "bonus-metadata", user=user))
    day = meta["start"] or str(date.today())
    sem = asyncio.Semaphore(4)
    products: dict[int, dict] = {}
    groups: dict[str, dict] = {}
    failed = 0

    def add(items: list[dict], personal: bool = False) -> None:
        for p in items:
            p["personal"] = personal
            old = products.get(p["id"])
            if not old or (p.get("saving") or 0) > (old.get("saving") or 0):
                products[p["id"]] = p

    async def section(cat: str) -> None:
        nonlocal failed
        async with sem:
            try:
                data = await get_json(BONUS_SECTION_URL, f"bonus-sectie {cat}", user=user, params={
                    "application": "AHWEBSHOP", "date": day, "promotionType": "NATIONAL", "category": cat})
            except AHDataError:
                failed += 1
                return
        prods, grps = parse_bonus_section(data)
        add(prods)
        for g in grps:
            groups.setdefault(g["id"], g)

    await asyncio.gather(*(section(c) for c in meta["categories"]))
    if meta["categories"] and failed == len(meta["categories"]):
        raise AHDataError("De bonus kon niet worden opgehaald.")

    personal = 0
    if user:
        try:
            data = await get_json(BONUS_PERSONAL_URL, "persoonlijke bonus", params={"bonusStartDate": day})
            prods, grps = parse_bonus_section(data)
            add(prods, personal=True)
            personal = len(prods)
            for g in grps:
                groups.setdefault(g["id"], g)
        except AHDataError:
            pass  # persoonlijke bonus is extra

    async def resolve(g: dict) -> None:
        async with sem:
            try:
                data = await gql(BONUS_GROUP_QUERY, {"id": g["id"], "periodStart": meta["start"],
                                                     "periodEnd": meta["end"]}, "bonusgroep", user=user)
            except AHDataError:
                return
        promos = data.get("bonusPromotions") or []
        for promo in promos[:1]:
            add([p for p in (_bonus_product(x, g["mechanism"], g["id"]) for x in promo.get("products") or []) if p])

    unresolved = list(groups.values())
    await asyncio.gather(*(resolve(g) for g in unresolved[:MAX_GROUPS]))
    return {"start": meta["start"], "end": meta["end"], "products": products, "personal": personal,
            "groups": len(unresolved)}


def score_recipes(recipes: list[dict], bonus: dict[int, dict]) -> list[dict]:
    """Per recept: hoeveel gekoppelde ingrediënten in de bonus zijn (+ actie en geschatte besparing).

    `recipes`: [{"id", "name", "image_url", ..., "ingredients": [...]}]. Gesorteerd op aantal, dan dekking.
    """
    out = []
    for r in recipes:
        items, linked, seen = [], 0, set()
        for ing in r.get("ingredients") or []:
            if ing.get("skip"):
                continue
            pid = _int((ing.get("product") or {}).get("id"))
            if not pid:
                continue
            linked += 1
            b = bonus.get(pid) or bonus.get(str(pid))
            if not b or pid in seen:
                continue
            seen.add(pid)
            qty = max(1, int(ing.get("quantity") or 1))
            items.append({"text": ing.get("text", ""), "product_id": pid,
                          "name": b.get("title") or (ing.get("product") or {}).get("name", ""),
                          "mechanism": b.get("mechanism", ""),
                          "saving": round(b["saving"] * qty, 2) if b.get("saving") else None})
        if not items:
            continue
        savings = [i["saving"] for i in items if i["saving"]]
        out.append({**{k: v for k, v in r.items() if k != "ingredients"},
                    "bonus_count": len(items), "linked_count": linked,
                    "coverage": round(len(items) / linked, 2) if linked else 0.0,
                    "saving": round(sum(savings), 2) if savings else None, "items": items})
    out.sort(key=lambda x: (-x["bonus_count"], -x["coverage"], -(x["saving"] or 0), x.get("name", "")))
    return out


# ── 2. Favorietenlijsten (AH-productlijsten) ───────────────────────────


def parse_lists(data) -> list[dict]:
    rows = data if isinstance(data, list) else _first(data, "lists", "favoriteLists", "items", default=[]) or []
    out = []
    for r in rows:
        if not isinstance(r, dict) or not _first(r, "id", "listId"):
            continue
        out.append({"id": str(_first(r, "id", "listId")),
                    "name": str(_first(r, "description", "name", "title", default="") or "Lijst"),
                    "count": int(_first(r, "itemCount", "totalSize", "count", "size", default=0) or 0)})
    return out


async def get_lists() -> list[dict]:
    # De API wil een productId-parameter, maar geeft alle lijsten terug (zie appie-go).
    # De API wil een productId (geeft dan alle lijsten). appie-go gebruikt 1; live gaf dat 404 -> ook een echt id.
    last: AHDataError | None = None
    for params in ({"productId": 1}, {"productId": 197585}, {}):
        try:
            return parse_lists(await get_json(LISTS_URL, "favorietenlijsten", params=params))
        except AHDataError as e:
            last = e
    raise last or AHDataError("Je AH-lijsten konden niet worden opgehaald.")


LIST_ITEMS_QUERY = """query FavoriteListV2($ids: [String!]!) {
  favoriteListV2(ids: $ids) { id description totalSize items { id productId quantity } }
}"""


def _aliased_products_query(ids: list[int]) -> str:
    # Aliassen moeten statisch zijn; de ids zijn gevalideerde positieve ints.
    return "query ProductTitles {" + " ".join(f" p{i}: product(id: {pid}) {{ id title }}"
                                              for i, pid in enumerate(ids)) + " }"


async def product_titles(ids: list[int]) -> dict[int, str]:
    """Productnamen voor webshop-ids (één GraphQL-call per 50). Fout = lege namen (zacht)."""
    ids = list(dict.fromkeys(i for i in (_int(x) for x in ids) if i))
    out: dict[int, str] = {}
    for start in range(0, len(ids), 50):
        chunk = ids[start:start + 50]
        try:
            data = await gql(_aliased_products_query(chunk), None, "productnamen")
        except AHDataError:
            continue
        for i, pid in enumerate(chunk):
            title = _first(data.get(f"p{i}"), "title", "description")
            if title:
                out[pid] = str(title)
    return out


async def get_list_items(list_id: str) -> dict:
    data = await gql(LIST_ITEMS_QUERY, {"ids": [list_id.upper()]}, "lijst-items")
    lists = data.get("favoriteListV2")
    if isinstance(lists, dict):
        lists = [lists]
    if not lists:
        raise AHDataError("Deze AH-lijst bestaat niet (meer).")
    lst = lists[0] or {}
    items = []
    for it in lst.get("items") or []:
        pid = _int(_first(it, "productId", "webshopId", "id"))
        if pid:
            items.append({"product_id": pid, "quantity": max(1, int(_first(it, "quantity", default=1) or 1)),
                          "name": str(_first(it, "description", "title", "name", default="") or "")})
    missing = [i["product_id"] for i in items if not i["name"]]
    if missing:
        titles = await product_titles(missing)
        for i in items:
            i["name"] = i["name"] or titles.get(i["product_id"], "")
    return {"id": str(_first(lst, "id", default=list_id)), "name": str(_first(lst, "description", "name", default="")),
            "items": items}


def merge_items(*groups: list[dict]) -> list[dict]:
    """Producten uit meerdere bronnen samenvoegen: per product_id de aantallen optellen."""
    merged: dict[int, dict] = {}
    for group in groups:
        for it in group or []:
            pid = _int(it.get("product_id"))
            if not pid:
                continue
            qty = max(1, int(it.get("quantity") or 1))
            if pid in merged:
                merged[pid]["quantity"] += qty
                merged[pid]["name"] = merged[pid]["name"] or it.get("name", "")
            else:
                merged[pid] = {"product_id": pid, "quantity": qty, "name": it.get("name", "") or ""}
    return list(merged.values())


def is_basis(name: str) -> bool:
    return "basis" in (name or "").lower()


# ── 3. Allerhande-favorieten ───────────────────────────────────────────

# Allerhande bewaart favoriete recepten als "recipe collection": categorieën met recepten
# (schema: Query.recipeCollectionCategories -> [RecipeCollectionCategory{id name isDefault recipes{id type}}]).
FAVORITE_RECIPES_QUERIES = [
    # RecipeSummary heeft (live, 2026-10) geen "type"-veld; alleen id/title vragen
    ("recipeCollectionCategories", """query RecipeCollectionCategories {
  recipeCollectionCategories { id name isDefault recipes { id title } }
}"""),
    ("recipeCollectionCategories-ids", """query RecipeCollectionCategories {
  recipeCollectionCategories { id name isDefault recipes { id } }
}"""),
]


def parse_favorite_recipe_ids(data: dict) -> list[int]:
    cats = _first(data, "recipeCollectionCategories", "recipeCollectionCategory", default=[]) or []
    if isinstance(cats, dict):
        cats = [cats]
    ids: list[int] = []
    for cat in cats:
        for r in (cat or {}).get("recipes") or (cat or {}).get("list") or []:
            if not isinstance(r, dict):
                continue
            if "MEMBER" in str(r.get("type") or "").upper():
                continue  # eigen/gescrapete recepten van leden zijn geen Allerhande-recepten
            rid = _int(_first(r, "id", "recipeId"))
            if rid and rid not in ids:
                ids.append(rid)
    return ids


async def get_favorite_recipe_ids() -> list[int]:
    last: AHDataError | None = None
    for name, query in FAVORITE_RECIPES_QUERIES:
        try:
            data = await gql(query, None, f"Allerhande-favorieten ({name})")
        except AHDataError as e:
            last = e
            continue
        ids = parse_favorite_recipe_ids(data)
        logger.info("AH favorieten via %s: %d recepten (%s)", name, len(ids), str(data)[:200])
        return ids
    raise AHDataError("Je Allerhande-favorieten konden niet worden opgehaald.") from last


async def recipe_titles(ids: list[int]) -> dict[int, str]:
    out: dict[int, str] = {}
    for start in range(0, len(ids), 50):
        chunk = ids[start:start + 50]
        query = "query RecipeTitles {" + " ".join(f" r{i}: recipe(id: {rid}) {{ id title }}"
                                                  for i, rid in enumerate(chunk)) + " }"
        try:
            data = await gql(query, None, "recepttitels")
        except AHDataError:
            continue
        for i, rid in enumerate(chunk):
            if title := _first(data.get(f"r{i}"), "title"):
                out[rid] = str(title)
    return out


# ── 4. Standaardboodschappen (kassabonnen + online bestellingen) ───────

POS_RECEIPTS_QUERY = """query FetchPosReceipts($offset: Int!, $limit: Int!) {
  posReceiptsPage(pagination: {offset: $offset, limit: $limit}) { posReceipts { id dateTime } }
}"""
POS_RECEIPT_QUERY = """query FetchReceipt($id: String!) {
  posReceiptDetails(id: $id) { id products { id quantity name } }
}"""
CLOSED_ORDERS_QUERY = """query OrderFulfillmentsClosed {
  orderFulfillments(status: CLOSED) { result { orderId delivery { slot { date } } } }
}"""

SKIP_NAMES = re.compile(r"DRAAGTAS|TASJE|KOOPZEGEL|SPARZEGEL|STATIEGELD|EMBALLAGE|DIGITALE ZEGEL|BONUSKAART|"
                        r"KORTING|AIRMILES|PAKKET", re.I)


def _day(s) -> str:
    return str(s or "")[:10]


async def convert_pos_ids(ids: list[int]) -> dict[int, int]:
    """Kassabon-productids -> webshop-ids (productConvertId met aliassen, zoals appie-go)."""
    unique = list(dict.fromkeys(i for i in (_int(x) for x in ids) if i))
    out: dict[int, int] = {}
    for start in range(0, len(unique), 100):
        chunk = unique[start:start + 100]
        query = "query Convert {" + " ".join(f" p{i}: productConvertId(sourceId: {pid})"
                                             for i, pid in enumerate(chunk)) + " }"
        try:
            data = await gql(query, None, "kassabon-ids omzetten")
        except AHDataError:
            continue
        for i, pid in enumerate(chunk):
            if wid := _int(data.get(f"p{i}")):
                out[pid] = wid
    return out


async def receipt_trips(since: date, limit: int) -> list[dict]:
    data = await gql(POS_RECEIPTS_QUERY, {"offset": 0, "limit": 50}, "kassabonnen")
    page = _first(data, "posReceiptsPage", default={}) or {}
    rows = [r for r in (page.get("posReceipts") or []) if isinstance(r, dict) and r.get("id")]
    rows = [r for r in rows if _day(_first(r, "dateTime", "transactionMoment", "date")) >= str(since)]
    rows.sort(key=lambda r: _day(_first(r, "dateTime", "transactionMoment", "date")), reverse=True)
    rows = rows[:limit]
    sem = asyncio.Semaphore(4)

    async def detail(r: dict) -> dict | None:
        async with sem:
            try:
                d = await gql(POS_RECEIPT_QUERY, {"id": str(r["id"])}, "kassabon")
            except AHDataError:
                return None
        det = _first(d, "posReceiptDetails", "posReceipt", default={}) or {}
        prods = [(p.get("id"), str(p.get("name") or "")) for p in det.get("products") or [] if isinstance(p, dict)]
        return {"date": _day(_first(r, "dateTime", "transactionMoment", "date")), "source": "kassabon",
                "pos": [(pid, name) for pid, name in prods if _int(pid) and not SKIP_NAMES.search(name)]}

    trips = [t for t in await asyncio.gather(*(detail(r) for r in rows)) if t]
    mapping = await convert_pos_ids([pid for t in trips for pid, _ in t["pos"]])
    for t in trips:
        t["products"] = {}
        for pos_id, name in t.pop("pos"):
            if wid := mapping.get(_int(pos_id)):
                t["products"][wid] = name.title() if name.isupper() else name
    return trips


async def order_trips(since: date, limit: int) -> list[dict]:
    data = await gql(CLOSED_ORDERS_QUERY, None, "eerdere bestellingen")
    res = (_first(data, "orderFulfillments", default={}) or {}).get("result") or []
    rows = []
    for f in res:
        oid = _int(_first(f, "orderId", "id"))
        day = _day(_first(((f or {}).get("delivery") or {}).get("slot"), "date") or _first(f, "deliveryDate"))
        if oid and day >= str(since):
            rows.append((day, oid))
    rows.sort(reverse=True)
    sem = asyncio.Semaphore(4)

    async def detail(day: str, oid: int) -> dict | None:
        async with sem:
            try:
                d = await get_json(ORDER_DETAILS_URL.format(order_id=oid), "bestelling")
            except AHDataError:
                return None
        products = {}
        for group in _first(d, "groupedProductsInTaxonomy", default=[]) or []:
            for op in (group or {}).get("orderedProducts") or []:
                prod = (op or {}).get("product") or {}
                pid = _int(_first(prod, "webshopId", "id") or (op or {}).get("productId"))
                if pid and int(_first(op, "quantity", "amount", default=1) or 0) > 0:
                    products[pid] = str(_first(prod, "title", "description", default="") or "")
        for op in _first(d, "orderedProducts", default=[]) or []:  # platte variant
            prod = (op or {}).get("product") or {}
            if pid := _int(_first(prod, "webshopId", "id")):
                products[pid] = str(_first(prod, "title", default="") or "")
        return {"date": day, "source": "bestelling", "products": products}

    return [t for t in await asyncio.gather(*(detail(d, o) for d, o in rows[:limit])) if t]


def compute_staples(trips: list[dict], exclude: set[int], basislijst: list[dict] | None = None,
                    min_times: int = 3, min_share: float = 0.4, max_trips: int = 20) -> list[dict]:
    """Vaak gekochte producten: in >= `min_share` van de boodschappenrondes én >= `min_times` keer.

    Producten uit `exclude` (al in de recepten van de week) vallen weg. De items van de Basislijst
    komen er altijd bij (gemarkeerd `in_basislijst`), behalve als ze al in de recepten zitten.
    """
    trips = sorted(trips, key=lambda t: t.get("date", ""), reverse=True)[:max_trips]
    stats: dict[int, dict] = {}
    for t in trips:
        for pid, name in (t.get("products") or {}).items():
            pid = _int(pid)
            if not pid:
                continue
            s = stats.setdefault(pid, {"product_id": pid, "name": "", "times": 0, "last_bought": "",
                                       "in_basislijst": False})
            s["times"] += 1
            # Namen uit online bestellingen zijn netter dan de afkortingen op de kassabon.
            if name and (not s["name"] or t.get("source") == "bestelling"):
                s["name"] = name
            s["last_bought"] = max(s["last_bought"], t.get("date", ""))
    need = max(min_times, min_share * len(trips))
    out = {pid: s for pid, s in stats.items() if s["times"] >= need and pid not in exclude}
    for it in basislijst or []:
        pid = _int(it.get("product_id"))
        if not pid or pid in exclude:
            continue
        s = out.get(pid) or dict(stats.get(pid) or {"product_id": pid, "name": "", "times": 0, "last_bought": ""})
        s["in_basislijst"] = True
        s["name"] = it.get("name") or s.get("name") or ""
        out[pid] = s
    rows = list(out.values())
    rows.sort(key=lambda s: (not s["in_basislijst"], -s["times"], s["name"].lower()))
    return rows


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def is_fresh(iso: str, hours: float) -> bool:
    try:
        return datetime.now() - datetime.fromisoformat(iso) < timedelta(hours=hours)
    except (TypeError, ValueError):
        return False
