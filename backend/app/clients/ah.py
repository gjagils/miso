import asyncio
import html
import time
from typing import Callable

import httpx

from app.logging_config import logger

AH_AUTH_URL = "https://api.ah.nl/mobile-auth/v1/auth/token/anonymous"
AH_TOKEN_URL = "https://api.ah.nl/mobile-auth/v1/auth/token"
AH_AUTHORIZE_URL = "https://login.ah.nl/secure/oauth/authorize"
AH_REDIRECT_URI = "appie://login-exit"
AH_REFRESH_URL = "https://api.ah.nl/mobile-auth/v1/auth/token/refresh"
AH_SEARCH_URL = "https://api.ah.nl/mobile-services/product/search/v2"
AH_CART_URL = "https://api.ah.nl/mobile-services/shoppinglist/v2/items"
# Mandje = de actieve (nog niet afgerekende) bestelling. Miso vult/leegt alleen; afrekenen bestaat hier niet.
AH_ORDER_ITEMS_URL = "https://api.ah.nl/mobile-services/order/v1/items?sortBy=DEFAULT"
AH_ORDER_ACTIVE_URL = "https://api.ah.nl/mobile-services/order/v1/summaries/active?sortBy=DEFAULT"
AH_ADD_MULTIPLE_URL = "https://www.ah.nl/mijnlijst/add-multiple"
AH_GRAPHQL_URL = "https://api.ah.nl/graphql"
AH_RECIPE_URL = "https://www.ah.nl/allerhande/recept/R-R{id}/{slug}"

DEFAULT_HEADERS = {
    "User-Agent": "Appie/8.22.3",
    "Content-Type": "application/json",
    "x-application": "AHWEBSHOP",
}


SEARCH_GQL = """query SearchProducts($q: String!) {
  searchProducts(input: {query: $q}) {
    products { id title brand salesUnitSize category taxonomies { name } icons
      price { now { amount } was { amount } unitInfo { description } }
      availability { isOrderable } imagePack { small { url } medium { url } } }
  }
}"""


def build_add_multiple_url(items: list[dict]) -> str:
    """Link die producten via de eigen AH-sessie van de gebruiker op 'Mijn lijst' zet (geen token nodig)."""
    from urllib.parse import urlencode

    params = [("p", f"{i['product_id']}:{max(1, int(round(i.get('quantity', 1))))}") for i in items if i.get("product_id")]
    return f"{AH_ADD_MULTIPLE_URL}?{urlencode(params)}"


def build_order_items(items: list[dict]) -> list[dict]:
    """Body-items voor PUT order/v1/items (mandje). Dubbele productId's samenvoegen; quantity 0 = verwijderen."""
    merged: dict[int, dict] = {}
    for item in items:
        pid = item["product_id"]
        qty = max(0, int(item.get("quantity", 1)))
        if pid in merged:
            merged[pid]["quantity"] += qty
        else:
            merged[pid] = {"productId": pid, "quantity": qty, "originCode": "PRD", "description": "",
                           "strikethrough": False}
    return list(merged.values())


def build_list_items(items: list[dict]) -> list[dict]:
    """Body-items voor PATCH shoppinglist/v2/items (zoals de AH-app/appie-go): met `description`
    (productnaam) en `strikeThrough`; dubbele productId's worden samengevoegd (AH weigert die)."""
    merged: dict[int, dict] = {}
    for item in items:
        pid = item["product_id"]
        qty = max(1, int(item.get("quantity", 1)))
        if pid in merged:
            merged[pid]["quantity"] += qty
        else:
            merged[pid] = {
                "productId": pid,
                "quantity": qty,
                "description": item.get("name") or "",
                "originCode": "PRD",
                "type": "SHOPPABLE",
                "strikeThrough": False,
            }
    return list(merged.values())


# ── Netjes blijven tegen de (onofficiële) AH-API ───────────────────────
# Max. 3 tegelijk, minimaal 0,15 s tussen aanroepen, terugtrekken bij 429/5xx, en zoekresultaten 6 uur
# bewaren: "alles opnieuw koppelen" vraagt veel dezelfde zoektermen op.
_AH_SEM = asyncio.Semaphore(3)
_AH_PACE = {"last": 0.0}
_AH_PACE_LOCK = asyncio.Lock()
MIN_GAP_S = 0.15
SEARCH_TTL_S = 6 * 3600
_SEARCH_CACHE: dict[str, tuple[float, list[dict]]] = {}
_SEARCH_CACHE_MAX = 4000
RETRY_STATUS = {429, 500, 502, 503, 504}


async def _polite(send: Callable) -> httpx.Response:
    """Voer een AH-request uit met tempo-limiet en backoff. `send` is een coroutine-factory."""
    for attempt in range(3):
        async with _AH_SEM:
            async with _AH_PACE_LOCK:
                wait = _AH_PACE["last"] + MIN_GAP_S - time.monotonic()
                if wait > 0:
                    await asyncio.sleep(wait)
                _AH_PACE["last"] = time.monotonic()
            try:
                resp = await send()
            except httpx.TransportError:
                if attempt == 2:
                    raise
                resp = None
        if resp is not None and (resp.status_code not in RETRY_STATUS or attempt == 2):
            return resp
        delay = 1.5 * (attempt + 1)
        if resp is not None and resp.headers.get("retry-after", "").isdigit():
            delay = min(30, int(resp.headers["retry-after"]))
        logger.warning("AH %s, opnieuw over %.1fs", resp.status_code if resp is not None else "netwerkfout", delay)
        await asyncio.sleep(delay)
    raise RuntimeError("unreachable")


def _cache_get(key: str) -> list[dict] | None:
    hit = _SEARCH_CACHE.get(key)
    if hit and time.monotonic() - hit[0] < SEARCH_TTL_S:
        return [dict(p) for p in hit[1]]
    return None


def _cache_put(key: str, products: list[dict]) -> None:
    if len(_SEARCH_CACHE) >= _SEARCH_CACHE_MAX:
        for k in sorted(_SEARCH_CACHE, key=lambda k: _SEARCH_CACHE[k][0])[: _SEARCH_CACHE_MAX // 4]:
            _SEARCH_CACHE.pop(k, None)
    _SEARCH_CACHE[key] = (time.monotonic(), [dict(p) for p in products])


class AHClient:
    def __init__(self) -> None:
        self._anonymous_token: str | None = None
        self._user_token: str | None = None
        self._user_refresh_token: str | None = None
        self._on_tokens_updated: Callable[[str, str], None] | None = None

    async def _get_anonymous_token(self) -> str:
        if self._anonymous_token:
            return self._anonymous_token
        async with httpx.AsyncClient() as client:
            logger.debug("Requesting anonymous AH token")
            resp = await client.post(
                AH_AUTH_URL,
                headers=DEFAULT_HEADERS,
                json={"clientId": "appie"},
            )
            resp.raise_for_status()
            data = resp.json()
            self._anonymous_token = data["access_token"]
            logger.info("Obtained anonymous AH token")
            return self._anonymous_token

    @staticmethod
    def get_login_url() -> str:
        """Return the AH OAuth2 login URL."""
        return (
            f"{AH_AUTHORIZE_URL}?client_id=appie"
            f"&redirect_uri={AH_REDIRECT_URI}&response_type=code"
        )

    async def exchange_code(self, code: str) -> dict:
        """Exchange an OAuth2 authorization code for tokens."""
        async with httpx.AsyncClient() as client:
            logger.info("Exchanging AH authorization code for tokens")
            resp = await client.post(
                AH_TOKEN_URL,
                headers=DEFAULT_HEADERS,
                json={"code": code, "clientId": "appie"},
            )
            resp.raise_for_status()
            data = resp.json()
            self._user_token = data["access_token"]
            self._user_refresh_token = data["refresh_token"]
            logger.info("AH code exchange successful")
            return data

    def set_user_tokens(
        self,
        access_token: str,
        refresh_token: str,
        on_tokens_updated: Callable[[str, str], None] | None = None,
    ) -> None:
        self._user_token = access_token
        self._user_refresh_token = refresh_token
        self._on_tokens_updated = on_tokens_updated

    def set_user_token(self, token: str) -> None:
        self._user_token = token

    async def _refresh_user_token(self) -> bool:
        if not self._user_refresh_token:
            return False
        try:
            async with httpx.AsyncClient() as client:
                logger.info("Refreshing AH user token")
                resp = await client.post(
                    AH_REFRESH_URL,
                    headers=DEFAULT_HEADERS,
                    json={
                        "refreshToken": self._user_refresh_token,
                        "clientId": "appie",
                    },
                )
                resp.raise_for_status()
                data = resp.json()
                self._user_token = data["access_token"]
                self._user_refresh_token = data["refresh_token"]
                logger.info("AH user token refreshed successfully")
                if self._on_tokens_updated:
                    self._on_tokens_updated(
                        self._user_token, self._user_refresh_token
                    )
                return True
        except Exception as e:
            logger.error("Failed to refresh AH user token: %s", e)
            return False

    async def search_products(self, query: str, size: int = 10) -> list[dict]:
        """Zoek producten zoals de Appie-app: GraphQL `searchProducts` begrijpt synoniemen en spelling
        ("parmaham" -> Prosciutto di parma, "scampi" -> garnalen). Het oude REST-zoeken (`search/v2`) zoekt
        alleen letterlijk in titels en blijft als aanvulling/reserve."""
        key = " ".join(query.lower().split())
        cached = _cache_get(key)
        if cached is not None:
            return cached[:size]
        try:
            products = await self._search_graphql(query)
        except Exception as e:  # noqa: BLE001 - dan het oude zoeken
            logger.warning("AH searchProducts failed for %r: %s", query, e)
            products = []
        if len(products) < 5:  # weinig of niets: aanvullen met letterlijk zoeken (scheelt de helft van de calls)
            seen = {p["id"] for p in products}
            products += [p for p in await self._search_legacy(query, 20) if p["id"] not in seen]
        _cache_put(key, products)
        return products[:size]

    async def _search_graphql(self, query: str) -> list[dict]:
        data = await self.graphql(SEARCH_GQL, {"q": query}, anonymous=True)
        out = []
        for p in (data.get("searchProducts") or {}).get("products") or []:
            price = p.get("price") or {}
            amount = (price.get("was") or {}).get("amount") or (price.get("now") or {}).get("amount")
            taxonomies = [t.get("name", "") for t in p.get("taxonomies") or []]
            images = (p.get("imagePack") or [{}])[0] or {}
            out.append({
                "id": p.get("id"),
                "name": p.get("title", ""),
                "unit_size": p.get("salesUnitSize") or "",
                "price": f"{amount:.2f}" if isinstance(amount, (int, float)) else "",
                "image_url": ((images.get("medium") or images.get("small")) or {}).get("url", ""),
                "brand": p.get("brand") or "",
                "category": (p.get("category") or "").split("/")[0] or (taxonomies[0] if taxonomies else ""),
                "available": (p.get("availability") or {}).get("isOrderable") is not False,
                "organic": "ORGANIC" in (p.get("icons") or []),
                "unit_price": ((price.get("unitInfo") or {}).get("description") or ""),
                # alcohol: hoofdafdeling wijn/bier (niet "wijnazijn" ergens diep in de indeling)
                "nix18": (p.get("category") or "").lower().startswith(("wijn", "bier", "sterke drank")),
            })
        return out

    async def _search_legacy(self, query: str, size: int = 10) -> list[dict]:
        token = await self._get_anonymous_token()
        headers = {**DEFAULT_HEADERS, "Authorization": f"Bearer {token}"}
        async with httpx.AsyncClient() as client:
            logger.debug("Searching AH products: %s", query)
            params = {"query": query, "sortOn": "RELEVANCE", "size": size}
            resp = await _polite(lambda: client.get(AH_SEARCH_URL, headers=headers, params=params, timeout=20))
            if resp.status_code == 401:
                logger.info("Anonymous token expired, refreshing")
                self._anonymous_token = None
                token = await self._get_anonymous_token()
                headers["Authorization"] = f"Bearer {token}"
                resp = await _polite(lambda: client.get(AH_SEARCH_URL, headers=headers, params=params, timeout=20))
            resp.raise_for_status()
            data = resp.json()

        products = []
        for product in data.get("products", []):
            products.append(
                {
                    "id": product.get("webshopId"),
                    "name": product.get("title", ""),
                    "unit_size": product.get("salesUnitSize", ""),
                    "price": str(product.get("priceBeforeBonus", product.get("currentPrice", ""))),
                    "image_url": (
                        product.get("images", [{}])[0].get("url", "")
                        if product.get("images")
                        else ""
                    ),
                    "brand": product.get("brand", ""),
                    "category": product.get("mainCategory", ""),
                    "available": bool(product.get("availableOnline", True)) and product.get("isOrderable", True) is not False,
                    "organic": "biologisch" in " ".join(product.get("propertyIcons") or []).lower(),
                    "unit_price": product.get("unitPriceDescription", ""),
                    "nix18": bool(product.get("nix18")),
                }
            )
        logger.debug("Found %d AH products for '%s'", len(products), query)
        return products

    async def graphql(self, query: str, variables: dict, anonymous: bool = False) -> dict:
        """Run a GraphQL query with the user token when set (unless `anonymous`), else an anonymous one."""
        async with httpx.AsyncClient(timeout=30) as client:
            for attempt in (1, 2):
                user = None if anonymous else self._user_token
                token = user or await self._get_anonymous_token()
                headers = {
                    **DEFAULT_HEADERS,
                    "x-client-name": "appie-ios",
                    "x-client-version": "9.28",
                    "Authorization": f"Bearer {token}",
                }
                body = {"query": query, "variables": variables}
                resp = await _polite(lambda: client.post(AH_GRAPHQL_URL, headers=headers, json=body))
                if resp.status_code == 401 and attempt == 1 and not user:
                    self._anonymous_token = None
                    continue
                resp.raise_for_status()
                body = resp.json()
                if body.get("errors"):
                    raise ValueError("AH: " + "; ".join(e.get("message", "") for e in body["errors"]))
                return body["data"]
        raise RuntimeError("unreachable")

    async def search_recipes(self, text: str, size: int = 12) -> list[dict]:
        query = """query RecipeSearch($query: RecipeSearchParams!) {
  recipeSearch(query: $query) {
    result { id title slug time { cook oven wait } serving { number type } images { url width } }
  }
}"""
        data = await self.graphql(query, {"query": {"searchText": text, "size": size}})
        return [
            {
                "id": r["id"],
                "title": html.unescape(r.get("title", "")),
                "slug": r.get("slug", ""),
                "url": AH_RECIPE_URL.format(id=r["id"], slug=r.get("slug", "")),
                "servings": _servings(r.get("serving")),
                "time": f"{(r.get('time') or {}).get('cook')} min" if (r.get("time") or {}).get("cook") else "",
                "image_url": _pick_image(r.get("images")),
            }
            for r in data["recipeSearch"]["result"]
        ]

    async def get_recipe(self, recipe_id: int) -> dict:
        query = """query Recipe($id: Int!) {
  recipe(id: $id) {
    id title description cookTime
    servings { number type }
    images { url width }
    ingredients { text name { singular } }
    preparation { steps }
  }
}"""
        data = await self.graphql(query, {"id": recipe_id})
        return data["recipe"]

    async def add_to_cart(self, items: list[dict]) -> dict:
        if not self._user_token:
            raise ValueError(
                "AH token niet ingesteld. Ga naar Instellingen."
            )
        headers = {
            **DEFAULT_HEADERS,
            "Authorization": f"Bearer {self._user_token}",
        }
        cart_items = build_list_items(items)
        async with httpx.AsyncClient() as client:
            logger.info("Adding %d items to AH cart", len(cart_items))
            resp = await client.patch(
                AH_CART_URL,
                headers=headers,
                json={"items": cart_items},
            )
            # If 401, try refreshing the token
            if resp.status_code == 401:
                logger.info("AH user token expired, attempting refresh")
                refreshed = await self._refresh_user_token()
                if not refreshed:
                    raise ValueError(
                        "AH token verlopen en refresh mislukt. "
                        "Voer een nieuw refresh token in via Instellingen."
                    )
                headers["Authorization"] = f"Bearer {self._user_token}"
                resp = await client.patch(
                    AH_CART_URL,
                    headers=headers,
                    json={"items": cart_items},
                )
            if resp.is_error:
                logger.error("AH shopping list %s: %s | body sent: %s", resp.status_code, resp.text[:500], cart_items[:5])
                raise ValueError(f"AH weigerde de boodschappenlijst ({resp.status_code}): {resp.text[:300]}")
            logger.info("Successfully added items to AH cart")
            return resp.json()


async def _user_call(client_obj, method: str, url: str, body: dict | None = None,
                     extra_headers: dict | None = None) -> httpx.Response:
    if not client_obj._user_token:
        raise ValueError("AH niet gekoppeld. Ga naar Instellingen.")
    async with httpx.AsyncClient(timeout=30) as client:
        for attempt in (1, 2):
            headers = {**DEFAULT_HEADERS, "Authorization": f"Bearer {client_obj._user_token}", **(extra_headers or {})}
            resp = await client.request(method, url, headers=headers, json=body)
            if resp.status_code == 401 and attempt == 1 and await client_obj._refresh_user_token():
                continue
            return resp
    return resp


def parse_shopping_list(data: dict) -> dict[int, int]:
    """Productnummer -> aantal op 'Mijn lijst' (afgestreepte en losse tekstregels tellen niet)."""
    out: dict[int, int] = {}
    for item in data.get("items") or []:
        if item.get("strikedthrough") or item.get("strikeThrough"):
            continue
        product = ((item.get("productDetails") or {}).get("product") or {})
        pid = product.get("webshopId") or item.get("productId")
        if pid:
            out[int(pid)] = out.get(int(pid), 0) + int(item.get("quantity") or 1)
    return out


async def get_shopping_list(client_obj) -> dict[int, int]:
    """Lees het echte AH-lijstje (GET shoppinglist/v2/items). Alleen lezen."""
    resp = await _user_call(client_obj, "GET", AH_CART_URL)
    if resp.is_error:
        raise ValueError(f"AH-lijstje lezen mislukt ({resp.status_code})")
    return parse_shopping_list(resp.json())


async def get_active_order(client_obj) -> dict:
    resp = await _user_call(client_obj, "GET", AH_ORDER_ACTIVE_URL)
    if resp.status_code == 404:
        return {"items": []}
    if resp.is_error:
        raise ValueError(f"AH-mandje ophalen mislukt ({resp.status_code}): {resp.text[:200]}")
    return resp.json()


async def set_order_items(client_obj, items: list[dict]) -> dict:
    """Zet aantallen in het mandje (0 = weghalen). Plaatst nooit een bestelling.

    De app stuurt het id van de actieve bestelling mee als header `appie-current-order-id` (zoals appie-go)."""
    order = await get_active_order(client_obj)
    order_id = order.get("id") or order.get("orderId")
    if not order_id:
        raise ValueError("Geen actief AH-mandje gevonden. Open de AH-app en kies eerst een bezorg- of ophaalmoment.")
    body = {"items": build_order_items(items)}
    resp = await _user_call(client_obj, "PUT", AH_ORDER_ITEMS_URL, body,
                            extra_headers={"appie-current-order-id": str(order_id)})
    if resp.is_error:
        logger.error("AH basket %s: %s | body: %s", resp.status_code, resp.text[:500], body["items"][:5])
        raise ValueError(f"AH weigerde het mandje ({resp.status_code}): {resp.text[:300]}")
    return resp.json() if resp.content else {}


def _pick_image(images: list[dict] | None, target: int = 440) -> str:
    """Kleinste Allerhande-afbeelding die minstens `target` px breed is (anders de grootste)."""
    imgs = [i for i in images or [] if i.get("url")]
    if not imgs:
        return ""
    wide = sorted((i for i in imgs if (i.get("width") or 0) >= target), key=lambda i: i.get("width") or 0)
    return (wide[0] if wide else max(imgs, key=lambda i: i.get("width") or 0))["url"]


def _servings(serving: dict | None) -> str:
    if not serving or not serving.get("number"):
        return ""
    return f"{serving['number']} {serving.get('type') or 'personen'}"


NO_BUY = {"water", "kraanwater", "kokend water", "ijswater"}


def convert_ah_recipe(r: dict) -> dict:
    """Map an Allerhande recipe (GraphQL `recipe`) to our recipe fields."""
    ingredients = []
    for ing in r.get("ingredients") or []:
        text = html.unescape(ing.get("text") or "").strip()
        if not text:
            continue
        search = html.unescape(((ing.get("name") or {}).get("singular")) or "").strip()
        skip = not search or search.lower() in NO_BUY
        ingredients.append({"text": text, "search": search, "skip": skip, "quantity": 1, "product": None})
    steps = [html.unescape(x).strip() for x in ((r.get("preparation") or {}).get("steps") or [])]
    cook = r.get("cookTime")
    return {
        "name": html.unescape(r.get("title") or "").strip(),
        "description": html.unescape(r.get("description") or "").strip(),
        "servings": _servings(r.get("servings")),
        "total_time": f"{cook} minuten" if cook else "",
        "ingredients": ingredients,
        "instructions": [x for x in steps if x],
        "image_url": _pick_image(r.get("images"), 612),
    }


ah_client = AHClient()
