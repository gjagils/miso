"""AH-gegevens: bonus -> recepten, AH-lijsten, Allerhande-favorieten, standaardboodschappen.

Geen echte AH-calls: `ah_data._http` wordt vervangen door een nep-AH met fixtures in de vorm van
appie-go's types (bonuspage, lists/v3, favoriteListV2, posReceipts, orderFulfillments, order details).
"""
import json
import re
from datetime import date, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api import ah_data as api
from app.api import routes
from app.clients import ah_data as ahd
from app.main import app
from app.models import PlanEntry, Recipe
from tests.test_allerhande import RAW
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)

TODAY = date.today()
D = lambda n: str(TODAY - timedelta(days=n))  # noqa: E731

# ── Fixtures in AH-vorm ────────────────────────────────────────────────

METADATA = {"periods": [{"bonusStartDate": D(2), "bonusEndDate": str(TODAY + timedelta(days=4)), "tabs": [
    {"description": "Alle bonus", "urlMetadataList": [
        {"url": "x", "count": 3, "bonusType": "NATIONAL", "description": "Vlees, kip, vis, vega"},
        {"url": "y", "count": 2, "bonusType": "NATIONAL", "description": "Aardappel, groente, fruit"},
        {"url": "z", "count": 9, "bonusType": "ETOS", "description": "Etos"},
    ]}]}]}

SECTIONS = {
    "Vlees, kip, vis, vega": {"sectionType": "x", "bonusGroupOrProducts": [
        {"product": {"webshopId": 1, "title": "AH Kipfilet", "isBonus": True, "bonusMechanism": "25% korting",
                     "currentPrice": 4.5, "priceBeforeBonus": 6.0}},
        {"bonusGroup": {"id": "G1", "segmentDescription": "Alle AH gehakt", "discountDescription": "1+1 gratis",
                        "products": [{"webshopId": 2, "title": "AH Rundergehakt", "priceBeforeBonus": 5.0}]}},
    ]},
    "Aardappel, groente, fruit": {"bonusGroupOrProducts": [
        {"bonusGroup": {"id": "G2", "segmentDescription": "Alle AH paprika's", "discountDescription": "2e halve prijs",
                        "exampleFromPrice": 2.0, "exampleForPrice": 1.5, "products": []}},
    ]},
}
PERSONAL = {"bonusGroupOrProducts": [{"product": {"webshopId": 4, "title": "AH Rijst", "bonusMechanism": "Bonus Box",
                                                  "currentPrice": 1.0, "priceBeforeBonus": 2.0}}]}
GROUP_G2 = {"bonusPromotions": [{"id": "G2", "title": "Alle AH paprika's", "products": [
    {"id": 3, "title": "AH Paprika rood", "priceV2": {"now": {"amount": 0.0}, "was": {"amount": 2.0},
                                                       "promotionLabel": {"tiers": [{"mechanism": "X", "description": "2e halve prijs"}]}}}]}]}

LISTS = [
    {"id": "aaaa-1", "description": "Basislijst", "itemCount": 3, "hasFavoriteProduct": False},
    {"id": "bbbb-2", "description": "Lasagne", "itemCount": 2},
    {"id": "cccc-3", "name": "Leeg", "totalSize": 0},
]
LIST_ITEMS = {
    "AAAA-1": [{"id": "i1", "productId": 10, "quantity": 2}, {"id": "i2", "productId": 11, "quantity": 1},
               {"id": "i3", "productId": 1, "quantity": 1}],
    "BBBB-2": [{"id": "i4", "productId": 10, "quantity": 1}, {"id": "i5", "productId": 12, "quantity": 0}],
}
TITLES = {10: "AH Halfvolle melk", 11: "AH Pindakaas", 12: "AH Lasagnebladen", 1: "AH Kipfilet"}

RECEIPTS = [{"id": f"r{n}", "dateTime": f"{D(n * 7)}T10:00:00Z"} for n in range(5)] + \
    [{"id": "old", "dateTime": f"{D(200)}T10:00:00Z"}]
RECEIPT_PRODUCTS = {  # kassabon-productids (POS) -> per bon
    "r0": [(901, "AH HALFV MELK"), (902, "AH BANANEN"), (999, "DRAAGTAS")],
    "r1": [(901, "AH HALFV MELK"), (903, "AH KIPFILET")],
    "r2": [(901, "AH HALFV MELK"), (902, "AH BANANEN"), (903, "AH KIPFILET")],
    "r3": [(903, "AH KIPFILET"), (904, "AH DROP")],
    "r4": [(905, "ONBEKEND")],
    "old": [(904, "AH DROP")],
}
POS_TO_WEBSHOP = {901: 10, 902: 20, 903: 1, 904: 30, 905: -1}
ORDERS = {"orderFulfillments": {"result": [
    {"orderId": 7001, "delivery": {"slot": {"date": D(3)}},
     "totalPrice": {"beforeDiscount": 61.0, "afterDiscount": 55.5, "discount": 5.5, "totalPrice": 55.5}},
    {"orderId": 7002, "delivery": {"slot": {"date": D(10)}}},
    {"orderId": 7999, "delivery": {"slot": {"date": D(300)}}},
]}}
ORDER_DETAILS = {  # (webshopId, titel, prijs vóór bonus, huidige prijs, bonus?)
    7001: [(20, "AH Bananen tros", 1.99, 1.99, False), (30, "Venco drop", 2.5, None, True)],
    7002: [(20, "AH Bananen tros", 1.99, 1.99, False), (10, "AH Halfvolle melk", 1.25, 1.25, False)],
}
RECEIPT_AMOUNTS = {"r0": 12.34, "r1": 8.0}  # totalAmount op de bon; andere bonnen zonder

FAV_RECIPES = {"recipeCollectionCategories": [
    {"id": 1, "name": "Alle favorieten", "isDefault": True,
     "recipes": [{"id": 101, "type": "RECIPE"}, {"id": 102, "type": "RECIPE"}, {"id": 900, "type": "MEMBER_RECIPE"}]},
    {"id": 2, "name": "Pasta", "isDefault": False, "recipes": [{"id": 101, "type": "RECIPE"}]},
]}


class FakeAH:
    """Nep-api.ah.nl: beantwoordt REST en GraphQL op basis van de fixtures hierboven."""

    def __init__(self):
        self.calls: list[str] = []
        self.fail: set[str] = set()

    def _resp(self, method, url, status, data):
        return httpx.Response(status, json=data, request=httpx.Request(method, url))

    async def __call__(self, method, url, *, params=None, body=None, user=True):
        params = params or {}
        name = url
        if url.endswith("/graphql"):
            q = body["query"]
            name = "gql:" + re.search(r"(query|mutation)\s+(\w+)", q).group(2)
        self.calls.append(name)
        if any(f in name for f in self.fail):
            return self._resp(method, url, 500, {"message": "kapot"})
        if "bonuspage/v3/metadata" in url:
            return self._resp(method, url, 200, METADATA)
        if "bonuspage/v2/section" in url:
            return self._resp(method, url, 200, SECTIONS.get(params["category"], {}))
        if "bonuspage/v1/personal" in url:
            return self._resp(method, url, 200, PERSONAL)
        if "lists/v3/lists" in url:
            return self._resp(method, url, 200, LISTS)
        m = re.search(r"order/v1/(\d+)/details-grouped-by-taxonomy", url)
        if m:
            prods = ORDER_DETAILS.get(int(m.group(1)), [])
            return self._resp(method, url, 200, {"orderId": int(m.group(1)), "groupedProductsInTaxonomy": [
                {"taxonomyName": "Zuivel", "orderedProducts": [
                    {"amount": 1, "quantity": 2 if pid == 20 else 1,
                     "product": {"webshopId": pid, "title": t, "priceBeforeBonus": was, "currentPrice": now,
                                 "isBonus": bonus, "mainCategory": "Fruit" if pid == 20 else ""}}
                    for pid, t, was, now, bonus in prods]}]})
        if name.startswith("gql:"):
            return self._resp(method, url, 200, {"data": self._gql(name[4:], body)})
        return self._resp(method, url, 404, {"message": "onbekend"})

    def _gql(self, op, body):
        q, v = body["query"], body.get("variables") or {}
        aliases = re.findall(r"(\w+): \w+\((?:id|sourceId): (\d+)\)", q)
        if op == "FetchBonusPromotionWithProducts":
            return GROUP_G2 if v["id"] == "G2" else {"bonusPromotions": []}
        if op == "FavoriteListV2":
            lid = v["ids"][0]
            return {"favoriteListV2": [{"id": lid, "description": "x", "items": LIST_ITEMS.get(lid, [])}]}
        if op == "ProductTitles":
            return {a: {"id": int(i), "title": TITLES.get(int(i), "")} for a, i in aliases}
        if op == "RecipeCollectionCategories":
            return FAV_RECIPES
        if op == "RecipeTitles":
            return {a: {"id": int(i), "title": f"Recept {i}"} for a, i in aliases}
        if op == "FetchPosReceipts":  # alleen bedragen als de query erom vraagt (zoals echte GraphQL)
            return {"posReceiptsPage": {"posReceipts": [
                {**r, **({"totalAmount": {"amount": RECEIPT_AMOUNTS[r["id"]]}}
                         if r["id"] in RECEIPT_AMOUNTS and "totalAmount" in q else {})}
                for r in RECEIPTS]}}
        if op == "FetchReceipt":
            return {"posReceiptDetails": {"id": v["id"], "products": [
                {"id": pid, "quantity": 1, "name": n, "price": {"amount": 1.5}, "amount": {"amount": 1.5}}
                for pid, n in RECEIPT_PRODUCTS[v["id"]]],
                "discounts": [{"name": "BONUS", "amount": {"amount": -0.5}}] if v["id"] == "r0" else [],
                "payments": [{"method": "PIN", "amount": {"amount": 4.0}}]}}
        if op == "Convert":
            return {a: POS_TO_WEBSHOP.get(int(i)) for a, i in aliases}
        if op == "OrderFulfillmentsClosed":
            if "totalPrice" in q:
                return ORDERS
            return {"orderFulfillments": {"result": [{k: v for k, v in r.items() if k != "totalPrice"}
                                                     for r in ORDERS["orderFulfillments"]["result"]]}}
        raise AssertionError(f"onverwachte GraphQL {op}")


@pytest.fixture()
def ah(monkeypatch):
    fake = FakeAH()
    monkeypatch.setattr(ahd, "_http", fake)
    return fake


@pytest.fixture()
def linked(db):  # noqa: F811
    routes._set_setting(db, "ah_user_token", "access")
    routes._set_setting(db, "ah_refresh_token", "refresh")
    return db


@pytest.fixture()
def pushed(monkeypatch):
    items: list[list[dict]] = []

    async def fake_add(batch):
        items.append(batch)
        return {}
    monkeypatch.setattr(api.ah_client, "add_to_cart", fake_add)
    return items


# ── 1. Bonus ───────────────────────────────────────────────────────────


def test_estimate_saving():
    assert ahd.estimate_saving("25% korting", 4.5, 6.0) == 1.5
    assert ahd.estimate_saving("25% korting", None, 4.0) == 1.0
    assert ahd.estimate_saving("1+1 gratis", None, 5.0) == 2.5
    assert ahd.estimate_saving("2+1 gratis", None, 3.0) == 1.0
    assert ahd.estimate_saving("2e halve prijs", None, 2.0) == 0.5
    assert ahd.estimate_saving("Bonus", None, None) is None


def test_bonus_recipes_sorted_by_coverage_and_cached(linked, ah):
    a = _recipe(linked, "Kip met paprika", [_ing("kip", 1), _ing("gehakt", 2, qty=2), _ing("paprika", 3),
                                             _ing("zout", 1, skip=True), _ing("ui", 50)])
    b = _recipe(linked, "Rijst", [_ing("rijst", 4), _ing("ui", 50)])
    _recipe(linked, "Niks", [_ing("ui", 50)])
    client = TestClient(app)

    resp = client.get("/api/bonus/recipes").json()
    assert resp["ok"] and [r["id"] for r in resp["recipes"]] == [a.id, b.id]
    top = resp["recipes"][0]
    assert top["bonus_count"] == 3 and top["linked_count"] == 4 and top["coverage"] == 0.75
    by_pid = {i["product_id"]: i for i in top["items"]}
    assert by_pid[1]["mechanism"] == "25% korting" and by_pid[1]["saving"] == 1.5
    assert by_pid[2]["mechanism"] == "1+1 gratis" and by_pid[2]["saving"] == 5.0  # 2,50 x 2 stuks
    assert by_pid[3]["mechanism"] == "2e halve prijs"  # groep opgelost via GraphQL bonusPromotions
    assert resp["recipes"][1]["items"][0]["mechanism"] == "Bonus Box"  # persoonlijke bonus
    assert "ingredients" not in top

    summary = client.get("/api/bonus").json()
    assert summary["ok"] and summary["count"] == 4 and summary["personal_count"] == 1
    assert summary["period"]["end"] == METADATA["periods"][0]["bonusEndDate"]
    # Alleen de NATIONAL-categorieën; daarna uit de cache (geen nieuwe calls)
    assert sum("bonuspage/v2/section" in c for c in ah.calls) == 2
    n = len(ah.calls)
    client.get("/api/bonus/recipes")
    assert len(ah.calls) == n

    # Verlopen periode -> opnieuw ophalen
    from app.models import AHBonusPeriod, AHPrice
    row = linked.query(AHBonusPeriod).one()
    assert row.products[1]["title"] == "AH Kipfilet"
    assert linked.query(AHPrice).filter_by(product_id=1).one().bonus_price == 4.5  # bonus is ook een prijssnapshot
    row.end = D(1)
    linked.commit()
    client.get("/api/bonus")
    assert len(ah.calls) > n


def test_bonus_fails_soft(db, ah, caplog):  # noqa: F811
    ah.fail = {"bonuspage"}
    resp = TestClient(app).get("/api/bonus/recipes").json()
    assert resp["ok"] is False and resp["error"]
    assert any("HTTP 500" in r.getMessage() for r in caplog.records)


# ── 2. AH-lijsten ──────────────────────────────────────────────────────


def test_ah_lists_and_merge_onto_shopping_list(linked, ah, pushed):
    client = TestClient(app)
    lists = client.get("/api/ah-lists").json()
    assert lists["ok"]
    assert [(l["name"], l["count"], l["is_basis"]) for l in lists["lists"]] == [
        ("Basislijst", 3, True), ("Lasagne", 2, False), ("Leeg", 0, False)]

    detail = client.get("/api/ah-lists/aaaa-1").json()
    assert detail["ok"] and {i["product_id"]: (i["name"], i["quantity"]) for i in detail["items"]} == {
        10: ("AH Halfvolle melk", 2), 11: ("AH Pindakaas", 1), 1: ("AH Kipfilet", 1)}

    assert client.post("/api/ah-lists/bbbb-2/to-list").json() == {"ok": True, "added": 2, "lists_failed": []}
    assert {i["product_id"]: i["quantity"] for i in pushed[-1]} == {10: 1, 12: 1}

    # Twee lijsten + standaardboodschappen: dubbele producten samengevoegd, één PATCH
    r = client.post("/api/ah-extras/to-list", json={"list_ids": ["aaaa-1", "bbbb-2"],
                                                    "products": [{"product_id": 11, "name": "Pindakaas", "quantity": 1},
                                                                 {"product_id": 99, "name": "Thee"}]}).json()
    assert r["ok"] and r["added"] == 5
    assert {i["product_id"]: i["quantity"] for i in pushed[-1]} == {10: 3, 11: 2, 1: 1, 12: 1, 99: 1}
    # en in AH-vorm zoals build_list_items het maakt
    from app.clients.ah import build_list_items
    body = build_list_items(pushed[-1])
    assert len({b["productId"] for b in body}) == len(body)
    assert all(b["type"] == "SHOPPABLE" and b["originCode"] == "PRD" for b in body)


def test_merge_items():
    out = ahd.merge_items([{"product_id": 1, "quantity": 2, "name": ""}], [{"product_id": "1", "name": "Melk"},
                                                                            {"product_id": None}])
    assert out == [{"product_id": 1, "quantity": 3, "name": "Melk"}]


# ── 3. Allerhande-favorieten ───────────────────────────────────────────


def test_favorite_recipes_import_dedupes(linked, ah, monkeypatch):
    existing = Recipe(name="Al bewaard", ah_recipe_id=101)
    linked.add(existing)
    linked.commit()
    fetched = []

    async def fake_get(recipe_id):
        fetched.append(recipe_id)
        return {**RAW, "id": recipe_id, "title": f"Recept {recipe_id}"}
    monkeypatch.setattr(routes.ah_client, "get_recipe", fake_get)
    client = TestClient(app)

    listed = client.get("/api/ah-favorite-recipes").json()
    assert listed["ok"] and listed["count"] == 2 and listed["new"] == 1
    assert [(r["id"], r["title"], r["imported"]) for r in listed["recipes"]] == [
        (101, "Recept 101", True), (102, "Recept 102", False)]

    first = client.post("/api/ah-favorite-recipes/import").json()
    assert first == {"ok": True, "total": 2, "imported": 1, "skipped": 1, "failed": 0, "errors": []}
    assert fetched == [102]
    second = client.post("/api/ah-favorite-recipes/import").json()
    assert second["imported"] == 0 and second["skipped"] == 2 and fetched == [102]
    assert linked.query(Recipe).filter(Recipe.ah_recipe_id == 102).count() == 1


def test_favorite_recipes_fallback_query_and_soft_fail(linked, ah):
    ah.fail = {"RecipeCollection"}
    resp = TestClient(app).get("/api/ah-favorite-recipes").json()
    assert resp["ok"] is False and "favorieten" in resp["error"]
    assert ah.calls.count("gql:RecipeCollectionCategories") == 2  # eerst met titels, dan alleen ids


# ── 4. Standaardboodschappen ───────────────────────────────────────────


def test_compute_staples_threshold_exclusion_and_basislijst():
    trips = [{"date": D(i), "source": "kassabon", "products": p} for i, p in enumerate([
        {1: "MELK", 2: "BROOD", 3: "KAAS"}, {1: "MELK", 2: "BROOD"}, {1: "MELK", 2: "BROOD", 3: "KAAS"},
        {1: "MELK", 4: "DROP"}, {5: "WIJN"}, {5: "WIJN"}, {5: "WIJN"}, {6: "X"}, {6: "X"}, {6: "X"}])]
    # 10 ritten: drempel = max(3, 0.4*10) = 4 -> alleen melk (4x)
    out = ahd.compute_staples(trips, exclude=set())
    assert [(s["product_id"], s["times"]) for s in out] == [(1, 4)]
    assert out[0]["last_bought"] == D(0) and out[0]["name"] == "MELK"
    # minder ritten: drempel 3
    out = ahd.compute_staples(trips[:4], exclude={2})
    assert [s["product_id"] for s in out] == [1]  # brood (3x) valt weg door de recepten van de week
    out = ahd.compute_staples(trips[:4], exclude=set(), basislijst=[{"product_id": 7, "name": "Pindakaas"},
                                                                    {"product_id": 1, "name": "AH Melk"}])
    by = {s["product_id"]: s for s in out}
    assert by[7]["in_basislijst"] and by[7]["times"] == 0
    assert by[1]["in_basislijst"] and by[1]["times"] == 4 and by[1]["name"] == "AH Melk"
    assert by[2]["in_basislijst"] is False and by[2]["times"] == 3


def test_staples_endpoint(linked, ah):
    monday = routes.monday_of(TODAY)
    r = _recipe(linked, "Kip", [_ing("kip", 1)])  # kipfilet (webshop 1) zit al in de week
    linked.add(PlanEntry(date=str(monday), recipe_id=r.id))
    linked.commit()
    client = TestClient(app)
    resp = client.get(f"/api/staples?week={monday}").json()
    assert resp["ok"], resp
    by = {s["product_id"]: s for s in resp["staples"]}
    # Ritten: 5 kassabonnen (oude valt buiten 12 weken) + 2 bestellingen = 7 -> drempel 3
    assert resp["source_counts"] == {"kassabonnen": 5, "bestellingen": 2, "ritten": 7, "basislijst": 3, "waarschijnlijk_op": 0}
    assert all(s["source"] == "vaak" for s in resp["staples"])
    assert by[10]["times"] == 4 and by[10]["in_basislijst"] and by[10]["name"] == "AH Halfvolle melk"
    assert by[20]["times"] == 4 and by[20]["name"] == "AH Bananen tros" and not by[20]["in_basislijst"]
    assert 30 not in by  # drop: 2 keer, onder de drempel
    assert 1 not in by   # kipfilet: al in de recepten van de week (ook al staat hij op de Basislijst)
    assert by[11]["in_basislijst"] and by[11]["times"] == 0
    assert "gql:FetchReceipt" in ah.calls and ah.calls.count("gql:Convert") == 1

    n = len(ah.calls)
    client.get(f"/api/staples?week={monday}")
    assert not any(c.startswith("gql:Fetch") or "Fulfillments" in c for c in ah.calls[n:])  # geschiedenis uit cache


def test_staples_one_source_down_still_works(linked, ah):
    ah.fail = {"FetchPosReceipts"}
    resp = TestClient(app).get("/api/staples").json()
    assert resp["ok"] and resp["source_counts"]["kassabonnen"] == 0 and resp["source_counts"]["bestellingen"] == 2
    ah.fail = {"FetchPosReceipts", "OrderFulfillments"}
    resp = TestClient(app).get("/api/staples?refresh=1").json()
    assert resp["ok"] is False and resp["error"]


# ── Zonder AH-koppeling ────────────────────────────────────────────────


def test_without_tokens_everything_is_ok_false(db, ah, pushed):  # noqa: F811
    client = TestClient(app)
    for resp in (client.get("/api/ah-lists"), client.get("/api/ah-lists/x"), client.post("/api/ah-lists/x/to-list"),
                 client.post("/api/ah-extras/to-list", json={"list_ids": ["x"]}),
                 client.get("/api/ah-favorite-recipes"), client.post("/api/ah-favorite-recipes/import"),
                 client.get("/api/staples")):
        assert resp.status_code == 200
        assert resp.json() == {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}
    assert ah.calls == [] and pushed == []
    # Bonus werkt anoniem (zonder persoonlijke bonus)
    resp = client.get("/api/bonus").json()
    assert resp["ok"] and resp["personal_count"] == 0
    assert not any("personal" in c for c in ah.calls)


def test_pages_render_with_new_sections(linked, ah):
    client = TestClient(app)
    page = client.get("/kiezen").text
    assert "Deze week in de bonus" in page and "Ook van je AH-lijsten" in page and "Vergeet je deze niet?" in page
    settings = client.get("/settings").text
    assert "Importeer mijn AH-favorieten" in settings and "Je AH-lijsten" in settings


def test_search_products_maps_app_search(monkeypatch):
    import asyncio

    from app.clients.ah import AHClient

    client = AHClient()

    from app.clients import ah as ah_mod

    ah_mod._SEARCH_CACHE.clear()

    async def fake_graphql(query, variables, anonymous=False):
        assert anonymous  # zoeken altijd anoniem: geen gedeelde gebruikerstokens
        assert "searchProducts" in query and variables == {"q": "parmaham"}
        return {"searchProducts": {"products": [{
            "id": 454461, "title": "AH Prosciutto di parma", "brand": "AH", "salesUnitSize": "90 g",
            "category": "Vleeswaren/Ham", "taxonomies": [{"name": "Vleeswaren"}], "icons": ["ORGANIC"],
            "price": {"now": {"amount": 3.19}, "was": {"amount": 3.79}, "unitInfo": None},
            "availability": {"isOrderable": True}, "imagePack": [{"small": {"url": "s"}, "medium": {"url": "m"}}],
        }] * 10}}

    async def no_legacy(query, size=10):
        raise AssertionError("niet nodig: app-zoeken gaf genoeg")

    monkeypatch.setattr(client, "graphql", fake_graphql)
    monkeypatch.setattr(client, "_search_legacy", no_legacy)
    p = asyncio.run(client.search_products("parmaham", size=10))[0]
    assert p["id"] == 454461 and p["unit_size"] == "90 g" and p["price"] == "3.79"
    assert p["category"] == "Vleeswaren" and p["organic"] and p["image_url"] == "m" and not p["nix18"]


def test_search_is_cached_and_paced(monkeypatch):
    import asyncio

    from app.clients import ah as ah_mod
    from app.clients.ah import AHClient

    ah_mod._SEARCH_CACHE.clear()
    calls = []

    async def fake_graphql(query, variables, anonymous=False):
        calls.append(variables["q"])
        return {"searchProducts": {"products": [{"id": i, "title": f"P{i}"} for i in range(10)]}}

    client = AHClient()
    monkeypatch.setattr(client, "graphql", fake_graphql)
    asyncio.run(client.search_products("Ui", 20))
    asyncio.run(client.search_products(" ui ", 20))
    assert calls == ["Ui"]


def test_polite_retries_on_429(monkeypatch):
    import asyncio

    import httpx

    from app.clients import ah as ah_mod

    real_sleep = asyncio.sleep
    monkeypatch.setattr(ah_mod.asyncio, "sleep", lambda s: real_sleep(0))
    answers = [httpx.Response(429), httpx.Response(200, json={})]

    async def send():
        return answers.pop(0)

    assert asyncio.run(ah_mod._polite(send)).status_code == 200


# ── 5. AH-datalaag: sync van ritten met bedragen, waarschijnlijk op, bonus per week ─────


def test_sync_trips_stores_amounts_and_only_fetches_new(linked, ah):
    from app import ah_sync
    from app.models import AHTrip

    client = TestClient(app)
    resp = client.post("/api/ah/sync").json()
    assert resp["ok"], resp
    # 6 kassabonnen + 3 bestellingen binnen 52 weken (de 'old'-bon van 200 dagen ook)
    assert resp["added"] == 9 and resp["orders"] == 3 and resp["receipts"] == 6 and resp["errors"] == []
    assert ah.calls.count("gql:Convert") == 1  # kassabon-ids in één keer omgezet
    trips = {(t.source, t.external_id): t for t in linked.query(AHTrip).all()}
    order = trips[("bestelling", "7001")]
    assert order.total == 55.5 and order.discount == 5.5 and order.date == D(3)
    by = {ln["product_id"]: ln for ln in order.lines}
    assert by[20] == {"product_id": 20, "name": "AH Bananen tros", "quantity": 2, "unit_price": 1.99,
                      "amount": 3.98, "bonus": False, "category": "Fruit"}
    assert by[30]["bonus"] and by[30]["unit_price"] == 2.5 and by[30]["amount"] == 2.5  # currentPrice null -> was-prijs
    assert trips[("bestelling", "7002")].total == 5.23  # geen totaal van AH: som van de regels (2x1,99 + 1,25)
    bon = trips[("kassabon", "r0")]
    assert bon.total == 12.34 and bon.discount == 0.5
    assert {ln["product_id"] for ln in bon.lines} == {10, 20}  # draagtas overgeslagen, POS-ids omgezet
    assert all(ln["unit_price"] == 1.5 and ln["amount"] == 1.5 for ln in bon.lines)
    assert trips[("kassabon", "r1")].total == 8.0
    assert trips[("kassabon", "r2")].total == 4.0  # geen totalAmount: betaald bedrag
    unknown = trips[("kassabon", "r4")].lines
    assert unknown[0]["product_id"] == 0 and unknown[0]["name"] == "Onbekend"  # -1 bij AH: naam blijft

    n = len(ah.calls)
    resp = client.post("/api/ah/sync").json()
    assert resp["added"] == 0 and resp["known"] == 9
    assert all(c in ("gql:FetchPosReceipts", "gql:OrderFulfillmentsClosed") for c in ah.calls[n:])  # alleen koppen
    status = client.get("/api/ah/sync/status").json()
    assert status["ok"] and status["linked"] and status["trips_total"] == 9 and status["last_run"]
    assert ah_sync.trips_as_dicts(ah_sync.trips_since(linked, TODAY - timedelta(days=30)))[0]["products"]


def test_sync_falls_back_to_minimal_queries(linked, ah, monkeypatch):
    """Kent AH de velden met bedragen niet (schema-onzekerheid), dan de minimale query."""
    orig = ahd.gql

    async def strict(query, variables, what, *, user=True):
        if "totalPrice" in query or "payments" in query or "totalAmount" in query:
            raise ahd.AHDataError(f"AH begreep de vraag niet ({what}).")
        return await orig(query, variables, what, user=user)
    monkeypatch.setattr(ahd, "gql", strict)
    resp = TestClient(app).post("/api/ah/sync").json()
    assert resp["ok"] and resp["added"] == 9 and resp["errors"] == []
    from app.models import AHTrip
    assert linked.query(AHTrip).filter_by(external_id="7001").one().total == 6.48  # som van regels i.p.v. AH-totaal


def test_staples_include_replenishment_due_and_bonus_for_week(linked, ah):
    from app.models import AHTrip

    for n in (21, 14, 7):  # wekelijks pindakaas (11): nu aan de beurt
        t = AHTrip(source="kassabon", external_id=f"p{n}", date=D(n))
        t.lines = [{"product_id": 11, "name": "AH Pindakaas", "quantity": 1, "unit_price": 2.0, "amount": 2.0, "bonus": False, "category": ""}]
        linked.add(t)
    linked.commit()
    client = TestClient(app)
    resp = client.get("/api/staples").json()
    first = resp["staples"][0]
    assert first["product_id"] == 11 and first["source"] == "ritme" and first["status"] == "op" and first["in_basislijst"]
    assert resp["source_counts"]["waarschijnlijk_op"] == 1
    assert resp["staples"][1]["source"] == "vaak"

    # Bonus voor de week waarvoor gepland wordt: volgende week -> periode 'next' als AH die al toont
    monday = routes.monday_of(TODAY)
    next_start = str(monday + timedelta(days=7))
    METADATA["periods"].append({"bonusStartDate": next_start, "bonusEndDate": str(monday + timedelta(days=13)), "tabs": [
        {"description": "Alle bonus", "urlMetadataList": [{"url": "x", "count": 1, "bonusType": "NATIONAL", "description": "Vlees, kip, vis, vega"}]}]})
    try:
        r = client.get(f"/api/bonus/recipes?week={next_start}").json()
        assert r["ok"] and r["period"]["start"] == next_start
        assert client.get(f"/api/bonus/recipes?week={monday}").json()["period"]["start"] == METADATA["periods"][0]["bonusStartDate"]
    finally:
        METADATA["periods"].pop()
