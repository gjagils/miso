"""/kiezen (Wat eten we?): pagina rendert en de JSON-endpoints van de flow accepteren onze payloads.

Geen echte AH-calls: alles wat naar AH zou gaan is gemockt.
"""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.api import routes, shopping
from app.clients.ah import _pick_image, convert_ah_recipe
from app.main import app
from app.models import PlanEntry, Recipe
from tests.test_allerhande import RAW
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)


def _no_ah_search(monkeypatch):
    async def fake_products(q, size=10):
        return []
    monkeypatch.setattr(routes.ah_client, "search_products", fake_products)


def test_kiezen_page_renders(db):
    _recipe(db, "Pasta pesto", [_ing("pasta", 5)])
    client = TestClient(app)
    resp = client.get("/kiezen")
    assert resp.status_code == 200
    assert "Wat eten we?" in resp.text and "Pasta pesto" in resp.text
    assert 'href="/kiezen"' in resp.text  # in de tabbar
    assert "/kiezen?week=" in client.get("/weekmenu").text


def test_kiezen_flow_endpoints(db, monkeypatch):
    _no_ah_search(monkeypatch)
    a = _recipe(db, "Pasta", [_ing("pasta", 5, qty=2), _ing("zout", skip=True), _ing("saffraan")])
    b = _recipe(db, "Curry", [_ing("pasta", 5), _ing("kip", 7)])
    client = TestClient(app)

    # Stap 1: zoeken in eigen recepten + Allerhande
    assert [r["name"] for r in client.get("/api/recipes?q=cur").json()["recipes"]] == ["Curry"]

    async def fake_search(text, size=12):
        return [{"id": 42, "title": "Kip & rijst", "slug": "kip", "url": "https://x", "servings": "4 personen",
                 "time": "30 min", "image_url": "https://static.ah.nl/x.jpg"}]

    async def fake_get(recipe_id):
        return {**RAW, "images": [{"url": "https://static.ah.nl/s.jpg", "width": 220},
                                  {"url": "https://static.ah.nl/m.jpg", "width": 612}]}

    monkeypatch.setattr(routes.ah_client, "search_recipes", fake_search)
    monkeypatch.setattr(routes.ah_client, "get_recipe", fake_get)
    found = client.get("/api/allerhande/search?q=kip").json()
    assert found["ok"] and found["results"][0]["id"] == 42 and found["results"][0]["saved"] is False
    added = client.post("/api/allerhande/add", data={"recipe_id": 42}).json()
    assert added["ok"] and db.get(Recipe, added["id"]).image_url == "https://static.ah.nl/m.jpg"

    # Stap 2: inplannen met behoud van bestaande dagen
    monday = routes.monday_of(date.today())
    week = client.get(f"/api/week?week={monday}").json()
    assert len(week["days"]) == 7
    days = {d["date"]: [r["id"] for r in d["recipes"]] for d in week["days"]}
    days[str(monday)].append(a.id)
    days[str(monday + timedelta(days=1))].append(b.id)
    resp = client.post("/api/plan", json={"week": str(monday), "days": days}).json()
    assert resp["ok"]
    assert db.query(PlanEntry).count() == 2

    # Stap 3: ingrediënten per recept (met product_id voor het samenvoegen)
    detail = client.get(f"/api/recipes/{a.id}").json()
    by_text = {i["text"]: i for i in detail["ingredients"]}
    assert by_text["pasta"]["product_id"] == 5 and by_text["pasta"]["quantity"] == 2
    assert by_text["zout"]["skip"] and by_text["saffraan"]["product_id"] is None

    link = client.post("/api/list-link", json={"recipe_ids": [a.id, b.id]}).json()
    assert link["ok"] and link["count"] == 2
    assert "p=5%3A3" in link["url"] and "p=7%3A1" in link["url"]

    # Zonder AH-koppeling: nette fout, geen AH-call
    sync = client.post("/api/plan/sync", json={"week": str(monday), "locked": True}).json()
    assert sync == {"ok": False, "error": "AH niet gekoppeld. Ga naar Instellingen."}
    fill = client.post("/api/basket/fill", json={"recipe_ids": [a.id, b.id]}).json()
    assert fill["ok"] is False and "gekoppeld" in fill["error"]
    assert client.post("/api/basket/clear", json={}).json() == {"ok": True, "removed": 0}


def test_sync_and_basket_with_mocked_ah(db, monkeypatch):
    _no_ah_search(monkeypatch)
    r = _recipe(db, "Pasta", [_ing("pasta", 5, qty=2)])
    monday = str(routes.monday_of(date.today()))
    client = TestClient(app)
    client.post("/api/plan", json={"week": monday, "days": {monday: [r.id]}})
    routes._set_setting(db, "ah_refresh_token", "x")

    pushed, order = [], {}

    async def fake_add(items):
        pushed.extend(items)
        return {}

    async def fake_active(client_):
        return {"items": [{"productId": pid, "quantity": q} for pid, q in order.items()]}

    async def fake_set(client_, items):
        order.update({i["product_id"]: i["quantity"] for i in items})

    monkeypatch.setattr(routes.ah_client, "add_to_cart", fake_add)
    monkeypatch.setattr(shopping, "get_active_order", fake_active)
    monkeypatch.setattr(shopping, "set_order_items", fake_set)

    sync = client.post("/api/plan/sync", json={"week": monday, "locked": True}).json()
    assert sync["ok"] and sync["added"] == 1 and sync["status"]["locked"]
    assert pushed == [{"product_id": 5, "quantity": 2, "name": "p5"}]

    assert client.post("/api/basket/fill", json={"recipe_ids": [r.id]}).json() == {"ok": True, "added": 1}
    assert order == {5: 2}
    assert client.post("/api/basket/clear", json={}).json() == {"ok": True, "removed": 1}
    assert order == {5: 0}


def test_pick_image():
    imgs = [{"url": "a", "width": 220}, {"url": "b", "width": 890}, {"url": "c", "width": 445}]
    assert _pick_image(imgs) == "c"
    assert _pick_image(imgs, 2000) == "b"
    assert _pick_image(None) == ""
    assert convert_ah_recipe(RAW)["image_url"] == ""
