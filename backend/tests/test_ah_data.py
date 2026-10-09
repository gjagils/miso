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
    {"orderId": 7001, "delivery": {"slot": {"date": D(3)}}},
    {"orderId": 7002, "delivery": {"slot": {"date": D(10)}}},
    {"orderId": 7999, "delivery": {"slot": {"date": D(300)}}},
]}}
ORDER_DETAILS = {
    7001: [(20, "AH Bananen tros"), (30, "Venco drop")],
    7002: [(20, "AH Bananen tros"), (10, "AH Halfvolle melk")],
}

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
                {"taxonomyName": "x", "orderedProducts": [
                    {"amount": 1, "quantity": 1, "product": {"webshopId": pid, "title": t}} for pid, t in prods]}]})
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
        if op == "FetchPosReceipts":
            return {"posReceiptsPage": {"posReceipts": RECEIPTS}}
        if op == "FetchReceipt":
            return {"posReceiptDetails": {"id": v["id"], "products": [
                {"id": pid, "quantity": 1, "name": n} for pid, n in RECEIPT_PRODUCTS[v["id"]]]}}
        if op == "Convert":
            return {a: POS_TO_WEBSHOP.get(int(i)) for a, i in aliases}
        if op == "OrderFulfillmentsClosed":
            return ORDERS
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
    cache = json.loads(routes._get_setting(linked, api.BONUS_CACHE))
    cache["end"] = D(1)
    routes._set_setting(linked, api.BONUS_CACHE, json.dumps(cache))
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
    assert resp["source_counts"] == {"kassabonnen": 5, "bestellingen": 2, "ritten": 7, "basislijst": 3}
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
