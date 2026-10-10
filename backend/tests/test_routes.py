import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api import routes
from app.database import Base, get_db
from app.main import app
from app.matching import MATCH_VERSION
from app.models import Recipe


@pytest.fixture()
def db():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    app.dependency_overrides[get_db] = lambda: session
    yield session
    app.dependency_overrides.clear()


def _recipe(db, name, ingredients):
    r = Recipe(name=name)
    r.ingredients = ingredients
    r.instructions = ["Kook."]
    db.add(r)
    db.commit()
    return r


def _ing(text, pid=None, qty=1, skip=False):
    product = {"id": pid, "name": f"p{pid}", "price": "1.00", "unit_size": "1 st"} if pid else None
    return {"text": text, "search": text, "skip": skip, "quantity": qty, "product": product, "match_v": MATCH_VERSION}


def test_aggregate_cart_sums_same_product_and_reports_unmatched(db):
    a = _recipe(db, "A", [_ing("ui", 1), _ing("rijst", 2, qty=2), _ing("water", skip=True)])
    b = _recipe(db, "B", [_ing("ui", 1, qty=3), _ing("saffraan")])
    cart, unmatched = routes.aggregate_cart([a, b])
    assert {i["product_id"]: i["quantity"] for i in cart} == {1: 4, 2: 2}
    assert unmatched == ["saffraan"]


def test_index_and_detail_render(db):
    r = _recipe(db, "Pasta", [_ing("pasta", 5)])
    client = TestClient(app)
    assert "Pasta" in client.get("/recepten").text
    assert client.get("/").status_code == 200
    assert "Pasta" in client.get(f"/recipe/{r.id}").text
    assert "Pasta" in client.get(f"/recipe/{r.id}/koken").text
    assert client.get("/recipe/999").status_code == 404
    assert client.get("/weekmenu").status_code == 200
    assert client.get("/settings").status_code == 200


def test_import_without_input_is_rejected(db):
    resp = TestClient(app).post("/api/import", data={})
    assert resp.status_code == 400


def test_plan_roundtrip_today_and_delete(db):
    from datetime import date

    r = _recipe(db, "Pasta", [_ing("pasta", 5)])
    client = TestClient(app)
    monday = routes.monday_of(date.today())
    day = str(date.today())  # Vandaag toont vanavond + de rest van de week, geen voorbije dagen
    resp = client.post("/api/plan", json={"week": str(monday), "days": {day: [r.id], "2000-01-01": [r.id]}}).json()
    assert resp["ok"] and resp["status"]["needed"] == 1  # date outside the week is ignored
    assert client.get(f"/weekmenu?week={monday}").status_code == 200
    home = client.get("/").text
    assert "Pasta" in home and "Start met koken" in home
    assert client.post(f"/recipe/{r.id}/delete", follow_redirects=False).status_code == 303
    assert db.get(Recipe, r.id) is None


def test_mealie_import_is_idempotent(db, monkeypatch):
    class FakeMealie:
        def __init__(self, url, token):
            pass

        async def list_slugs(self, client):
            return ["pasta", "leeg"]

        async def get_recipe(self, client, slug):
            if slug == "leeg":
                return {"id": "2", "name": "Leeg", "recipeIngredient": []}
            return {"id": "1", "name": "Pasta", "recipeYield": "4",
                    "recipeIngredient": [{"display": "250 g pasta", "food": {"name": "pasta"}}],
                    "recipeInstructions": [{"text": "Kook."}]}

        async def get_image(self, client, recipe_id):
            return None

    monkeypatch.setattr(routes, "MealieClient", FakeMealie)
    client = TestClient(app)
    first = client.post("/settings/mealie", data={"mealie_url": "http://mealie:9000", "mealie_token": "t"})
    assert "1 recepten geïmporteerd, 0 stonden er al, 1 mislukt" in first.text
    second = client.post("/settings/mealie", data={})
    assert "0 recepten geïmporteerd, 1 stonden er al" in second.text
    assert db.query(Recipe).count() == 1
    assert client.post("/settings/mealie", data={"mealie_url": "ftp://x"}).status_code == 200


def test_aggregate_cart_gluten_free_modes(db):
    pasta = _ing("500 g pasta", 1)
    pasta.update(gluten=True, gf_search="glutenvrije pasta", gf_product={"id": 9, "name": "gf pasta", "price": "2"})
    extra = _recipe(db, "Extra", [pasta])
    extra.gf_mode = "extra"
    cart, unmatched = routes.aggregate_cart([extra])
    assert {i["product_id"]: i["quantity"] for i in cart} == {1: 1, 9: 1} and not unmatched

    replace = _recipe(db, "Replace", [dict(pasta)])
    replace.gf_mode = "replace"
    cart, _ = routes.aggregate_cart([replace])
    assert {i["product_id"]: i["quantity"] for i in cart} == {9: 1}

    nogf = dict(pasta, gf_product=None)
    replace2 = _recipe(db, "R2", [nogf])
    replace2.gf_mode = "replace"
    cart, unmatched = routes.aggregate_cart([replace2])
    assert cart == [] and unmatched == ["500 g pasta (glutenvrij)"]

    off = _recipe(db, "Off", [dict(pasta)])
    cart, _ = routes.aggregate_cart([off])
    assert {i["product_id"] for i in cart} == {1}


def test_week_sync_pushes_only_the_difference(db, monkeypatch):
    from datetime import date

    from app.models import AppSetting

    db.add(AppSetting(key="ah_user_token", value="t"))
    a = _recipe(db, "A", [_ing("ui", 1, qty=2)])
    day = str(routes.monday_of(date.today()))
    client = TestClient(app)
    client.post("/api/plan", json={"week": day, "days": {day: [a.id]}})

    sent = []

    async def fake_add(items):
        sent.append(items)

    async def no_match(*args, **kwargs):
        return 0

    monkeypatch.setattr(routes.ah_client, "add_to_cart", fake_add)
    monkeypatch.setattr(routes, "_automatch", no_match)

    first = client.post("/api/plan/sync", json={"week": day, "locked": True}).json()
    assert first["ok"] and first["added"] == 1 and first["status"]["complete"] and first["status"]["locked"]
    assert sent[0][0]["quantity"] == 2

    # nothing changed -> nothing sent again
    again = client.post("/api/plan/sync", json={"week": day}).json()
    assert again["added"] == 0 and len(sent) == 1

    # same recipe planned a second day -> only the extra 2 are sent
    client.post("/api/plan", json={"week": day, "days": {day: [a.id], str(date.fromisoformat(day).replace(day=date.fromisoformat(day).day)): [a.id]}})
    status = client.get(f"/weekmenu?week={day}")
    assert status.status_code == 200


def test_gluten_suggest_and_save(db, monkeypatch):
    async def fake_suggest(name, texts):
        return {"mode": "extra", "note": "Aparte pasta", "items": {0: "glutenvrije pasta"}}

    monkeypatch.setattr(routes, "suggest_gluten_free", fake_suggest)
    r = _recipe(db, "Pasta", [_ing("pasta", 1), _ing("tomaat", 2)])
    client = TestClient(app)
    out = client.post(f"/api/recipe/{r.id}/gluten-suggest").json()
    assert out["ok"] and out["gf_mode"] == "extra"
    assert [i["gluten"] for i in out["ingredients"]] == [True, False]
    bad = client.post(f"/api/recipe/{r.id}/gluten", json={"gf_mode": "x", "ingredients": []})
    assert bad.status_code == 400


def test_pin_protects_everything(db, monkeypatch):
    monkeypatch.setattr("app.main.settings.app_pin", "1234")
    client = TestClient(app)
    assert client.get("/", follow_redirects=False).headers["location"] == "/login"
    assert client.get("/api/ah/search?q=x").status_code == 401
    assert client.post("/login", data={"pin": "0000"}).status_code == 401
    monkeypatch.setattr(routes.settings, "app_pin", "1234")
    ok = client.post("/login", data={"pin": "1234"}, follow_redirects=False)
    assert ok.status_code == 303 and "session" in ok.cookies
    assert client.get("/").status_code == 200


def test_json_api_for_ios_app(db):
    from datetime import date

    r = _recipe(db, "Pasta", [_ing("pasta", 1)])
    client = TestClient(app)
    listing = client.get("/api/recipes?q=pas").json()["recipes"]
    assert [x["name"] for x in listing] == ["Pasta"] and client.get("/api/recipes?q=zzz").json()["recipes"] == []
    detail = client.get(f"/api/recipes/{r.id}").json()
    assert detail["instructions"] == ["Kook."] and detail["ingredients"][0]["product"] == "p1"
    assert client.get("/api/recipes/999").status_code == 404
    week = client.get("/api/week").json()
    assert len(week["days"]) == 7 and week["week"] == str(routes.monday_of(date.today()))


def test_app_login_and_bearer_with_pin(db, monkeypatch):
    import app.api.json_api as json_api

    for module in (json_api.settings, routes.settings):
        monkeypatch.setattr(module, "app_pin", "1234")
    client = TestClient(app)
    assert client.get("/api/recipes").status_code == 401
    assert client.post("/api/login", json={"pin": "0000"}).status_code == 401
    token = client.post("/api/login", json={"pin": "1234"}).json()["token"]
    assert client.get("/api/recipes", headers={"Authorization": f"Bearer {token}"}).status_code == 200


def test_import_fetch_errors_are_understandable():
    import httpx

    req = httpx.Request("GET", "https://example.nl/r")
    err = httpx.HTTPStatusError("403", request=req, response=httpx.Response(403, request=req))
    msg = routes.fetch_error_text(err)
    assert "niet meelezen" in msg and "403" not in msg
    assert "bestaat niet" in routes.fetch_error_text(
        httpx.HTTPStatusError("404", request=req, response=httpx.Response(404, request=req)))


def test_import_text_keeps_source_link_and_uses_shared_photo(db, monkeypatch):
    import io as _io
    from PIL import Image as _Image

    async def fake_extract(text=None, images=None):
        return {"name": "Burrito bowl", "description": "", "servings": "4", "total_time": "",
                "ingredients": [{"text": "200 g rijst", "search": "rijst", "skip": False, "quantity": 1, "product": None}],
                "instructions": ["Kook."]}

    monkeypatch.setattr(routes, "extract_recipe", fake_extract)
    monkeypatch.setattr(routes, "IMAGE_DIR", "/tmp/miso-test-images")
    buf = _io.BytesIO(); _Image.new("RGB", (40, 30), "orange").save(buf, format="JPEG")
    client = TestClient(app)
    r = client.post("/api/import", data={"text": "Burrito bowl\\n200 g rijst", "source_url": "https://miljuschka.nl/x/"},
                    files={"photo": ("p.jpg", buf.getvalue(), "image/jpeg")}).json()
    assert r["ok"] and r["name"] == "Burrito bowl"
    recipe = db.get(Recipe, r["id"])
    assert recipe.source_url == "https://miljuschka.nl/x/" and recipe.image_url == f"/image/{recipe.id}"


def test_replace_photo_saves_upload(db, tmp_path, monkeypatch):
    import io

    from PIL import Image

    monkeypatch.setattr(routes, "IMAGE_DIR", str(tmp_path))
    r = _recipe(db, "Pasta", [])
    buf = io.BytesIO()
    Image.new("RGB", (40, 30), "red").save(buf, format="JPEG")
    client = TestClient(app)
    resp = client.post(f"/api/recipe/{r.id}/photo", files={"photo": ("p.jpg", buf.getvalue(), "image/jpeg")})
    assert resp.json()["image_url"].startswith(f"/image/{r.id}?v=")
    assert (tmp_path / f"{r.id}.jpg").exists()
    assert client.post(f"/api/recipe/{r.id}/photo", data={}).status_code == 400


def test_no_photo_filter_and_remove(db, tmp_path, monkeypatch):
    monkeypatch.setattr(routes, "IMAGE_DIR", str(tmp_path))
    with_photo = _recipe(db, "Met foto", [])
    with_photo.image_url = f"/image/{with_photo.id}"
    _recipe(db, "Zonder foto", [])
    db.commit()
    client = TestClient(app)
    page = client.get("/recepten?foto=nee").text
    assert "Zonder foto" in page and "Met foto" not in page and "Kies foto" in page
    assert "Zonder foto (1)" in client.get("/recepten").text
    assert client.post(f"/api/recipe/{with_photo.id}/photo/remove").json() == {"ok": True}
    assert "Met foto" in client.get("/recepten?foto=nee").text
    assert "Foto toevoegen" in client.get(f"/recipe/{with_photo.id}").text


def test_rematch_keeps_valid_product_when_search_is_empty(monkeypatch):
    import asyncio

    async def empty(query, size=20):
        return []

    monkeypatch.setattr(routes.ah_client, "search_products", empty)
    good = {"id": 1, "name": "AH Biologisch Basmati rijst", "unit_size": "400 g", "category": "Pasta, rijst, wereldkeuken"}
    bad = {"id": 2, "name": "AH Zoete kleine appeltjes", "unit_size": "4 stuks", "category": "Groente, aardappelen"}
    ings = [{"text": "400g basmatirijst", "search": "basmatirijst", "product": dict(good), "match_v": 1},
            {"text": "400g basmatirijst", "search": "basmatirijst", "product": dict(bad), "match_v": 1}]
    asyncio.run(routes._automatch(ings))
    assert ings[0]["product"]["id"] == 1
    assert ings[1]["product"] is None


def test_missing_page_groups_and_assigns(db):
    from app.models import ProductPreference

    a = _recipe(db, "A", [_ing("2 gele paprika's"), _ing("rijst", 2)])
    b = _recipe(db, "B", [_ing("1 gele paprika"), _ing("dragon")])
    client = TestClient(app)
    page = client.get("/dekking/ontbrekend").text
    assert "gele paprika" in page and "2×" in page and "gekoppeld aan een AH-product" in page
    lines = [{"recipe_id": a.id, "index": 0, "text": "2 gele paprika's"},
             {"recipe_id": b.id, "index": 0, "text": "1 gele paprika"}]
    product = {"id": 9, "name": "AH Paprika geel", "unit_size": "per stuk"}
    assert client.post("/api/missing/assign", json={"lines": lines, "product": product}).json()["updated"] == 2
    db.expire_all()
    assert db.get(Recipe, a.id).ingredients[0]["product"]["id"] == 9
    assert db.get(Recipe, a.id).ingredients[0]["manual"] is True
    assert db.query(ProductPreference).count() == 1
    skip = [{"recipe_id": b.id, "index": 1, "text": "dragon"}]
    client.post("/api/missing/assign", json={"lines": skip, "product": None})
    db.expire_all()
    assert db.get(Recipe, b.id).ingredients[1]["skip"] is True
    assert "gele paprika" not in client.get("/dekking/ontbrekend").text
    stale = [{"recipe_id": a.id, "index": 1, "text": "iets anders"}]
    assert client.post("/api/missing/assign", json={"lines": stale, "product": product}).json()["updated"] == 0


def test_favicon_is_public():
    resp = TestClient(app).get("/favicon.ico")
    assert resp.status_code == 200 and len(resp.content) > 100


def test_json_ingredient_update_edit_and_delete(db, monkeypatch):
    from app.models import PlanEntry, ProductPreference

    async def no_match(db_, recipe):
        return None

    monkeypatch.setattr(routes, "ensure_matched", no_match)
    r = _recipe(db, "Soep", [_ing("1 ui", 1), _ing("2 gele paprika's")])
    db.add(PlanEntry(date="2026-10-12", kind="recipe", recipe_id=r.id))
    db.commit()
    client = TestClient(app)
    product = {"id": 9, "name": "AH Paprika geel", "unit_size": "per stuk"}
    res = client.post(f"/api/recipes/{r.id}/ingredients/1", json={"text": "2 gele paprika's", "product": product}).json()
    assert res["ingredient"]["product_id"] == 9 and res["ingredient"]["manual"] and res["ingredient"]["quantity"] == 2
    assert db.query(ProductPreference).count() == 1
    assert client.post(f"/api/recipes/{r.id}/ingredients/0", json={"text": "1 ui", "skip": True}).json()["ingredient"]["skip"]
    assert client.post(f"/api/recipes/{r.id}/ingredients/0", json={"text": "fout", "skip": True}).status_code == 409
    edited = client.patch(f"/api/recipes/{r.id}", json={"name": "Paprikasoep", "instructions": ["Kook.", " "],
                                                        "ingredients": ["2 gele paprika's", "1 l bouillon"]}).json()
    assert edited["name"] == "Paprikasoep" and edited["instructions"] == ["Kook."]
    assert [i["text"] for i in edited["ingredients"]] == ["2 gele paprika's", "1 l bouillon"]
    assert edited["ingredients"][0]["product_id"] == 9  # ongewijzigde regel houdt zijn koppeling
    assert client.patch(f"/api/recipes/{r.id}", json={"name": " "}).status_code == 400
    assert "groups" in client.get("/api/missing").json()
    assert client.delete(f"/api/recipes/{r.id}").json() == {"ok": True}
    assert db.query(PlanEntry).count() == 0


def test_daily_backup(tmp_path, monkeypatch):
    import sqlite3
    from datetime import date

    from app import maintenance

    db_file = tmp_path / "miso.db"
    sqlite3.connect(db_file).execute("create table t(x)").connection.commit()
    (tmp_path / "images").mkdir()
    (tmp_path / "images" / "1.jpg").write_bytes(b"x")
    monkeypatch.setattr(maintenance, "DATA_DIR", str(tmp_path))
    monkeypatch.setattr(maintenance, "BACKUP_DIR", str(tmp_path / "backups"))
    monkeypatch.setattr(maintenance, "_db_path", lambda: str(db_file))
    made = maintenance.backup_now(date(2026, 10, 9))
    assert len(made) == 2
    assert maintenance.backup_now(date(2026, 10, 9)) == []  # één per dag
    for d in range(10, 30):
        maintenance.backup_now(date(2026, 10, d))
    assert len([f for f in (tmp_path / "backups").iterdir() if f.name.startswith("miso-")]) == maintenance.KEEP_DB


def test_week_sync_reads_real_ah_list(db, monkeypatch):
    from datetime import date

    from app.clients.ah import parse_shopping_list
    from app.models import AppSetting

    assert parse_shopping_list({"items": [
        {"quantity": 2, "strikedthrough": False, "productDetails": {"product": {"webshopId": 5}}},
        {"quantity": 1, "strikedthrough": True, "productDetails": {"product": {"webshopId": 6}}},
        {"quantity": 1, "type": "TEXT", "description": "wc-papier"},
    ]}) == {5: 2}

    db.add(AppSetting(key="ah_user_token", value="t"))
    a = _recipe(db, "A", [_ing("ui", 1, qty=3), _ing("rijst", 2, qty=1)])
    day = str(routes.monday_of(date.today()))
    client = TestClient(app)
    client.post("/api/plan/entries", json={"date": day, "kind": "recipe", "recipe_id": a.id})
    the_list = {1: 1}  # 1 ui staat er al (bijv. zelf toegevoegd); rijst is in de AH-app weggehaald
    sent = []

    async def fake_list(client_obj):
        return dict(the_list)

    async def fake_add(items):  # AH telt op
        sent.append(items)
        for i in items:
            the_list[i["product_id"]] = the_list.get(i["product_id"], 0) + i["quantity"]

    async def no_match(*args, **kwargs):
        return 0

    monkeypatch.setattr(routes, "get_shopping_list", fake_list)
    monkeypatch.setattr(routes.ah_client, "add_to_cart", fake_add)
    monkeypatch.setattr(routes, "_automatch", no_match)
    res = client.post("/api/plan/sync", json={"week": day}).json()
    assert res["ok"] and {i["product_id"]: i["quantity"] for i in sent[0]} == {1: 2, 2: 1}
    assert len(sent) == 1 and the_list == {1: 3, 2: 1}
    the_list.pop(2)  # weer weggehaald in de AH-app -> volgende sync zet hem terug
    client.post("/api/plan/sync", json={"week": day})
    assert sent[-1] == [{"product_id": 2, "quantity": 1, "name": "p2"}] or sent[-1][0]["product_id"] == 2


def test_tokens_encrypted_with_miso_secret(db, monkeypatch):
    from app.models import AppSetting
    from app.secretbox import encrypt_existing

    db.add(AppSetting(key="ah_refresh_token", value="oud-leesbaar"))
    db.commit()
    monkeypatch.delenv("MISO_SECRET", raising=False)
    routes._set_setting(db, "ah_user_token", "plain")
    assert db.query(AppSetting).filter_by(key="ah_user_token").one().value == "plain"  # zonder sleutel: zoals vroeger

    monkeypatch.setenv("MISO_SECRET", "een-lang-geheim-van-de-familie")
    routes._set_setting(db, "ah_user_token", "geheim-token")
    stored = db.query(AppSetting).filter_by(key="ah_user_token").one().value
    assert stored.startswith("enc:v1:") and "geheim-token" not in stored
    assert routes._get_setting(db, "ah_user_token") == "geheim-token"
    assert encrypt_existing(db) == 1  # de oude leesbare refresh-token
    assert routes._get_setting(db, "ah_refresh_token") == "oud-leesbaar"
    routes._set_setting(db, "household_size", "4")
    assert db.query(AppSetting).filter_by(key="household_size").one().value == "4"  # gewone instelling blijft leesbaar

    monkeypatch.setenv("MISO_SECRET", "andere-sleutel")
    assert routes._get_setting(db, "ah_user_token") == ""  # verkeerde sleutel: opnieuw koppelen


def test_favorites_feedback_review_and_archive(db, monkeypatch):
    from datetime import date, datetime, timedelta

    from app import usage
    from app.models import PlanEntry
    from app.usage import plan_stats, preference_score

    fav = _recipe(db, "Lasagne", [])
    never = _recipe(db, "Vergeten soep", [])
    never.created_at = datetime(2025, 1, 1)
    assert TestClient(app).get("/api/recipes-review").json()["too_early"]  # nog geen 30 keer gepland
    monkeypatch.setattr(usage, "MIN_PLANS", 3)
    for i in range(5):
        db.add(PlanEntry(date=str(date.today() - timedelta(days=30 + i)), kind="recipe", recipe_id=fav.id))
    db.commit()
    client = TestClient(app)
    assert client.patch(f"/api/recipes/{fav.id}/flags", json={"favorite": True}).json()["recipe"]["favorite"]
    assert client.post(f"/api/recipes/{fav.id}/feedback", json={"rating": "up"}).json()["thumbs_up"] == 1
    assert client.post(f"/api/recipes/{fav.id}/cooked").json()["cooked"] == 1  # zelfde dag: niet dubbel
    stats = plan_stats(db)
    db.refresh(fav)
    assert preference_score(fav, stats.get(fav.id)) > preference_score(never, stats.get(never.id))

    review = client.get("/api/recipes-review").json()
    assert review["total_plans"] == 5 and [r["name"] for r in review["recipes"]] == ["Vergeten soep"]
    assert "Vergeten soep" in client.get("/recepten/opruimen").text
    client.patch(f"/api/recipes/{never.id}/flags", json={"reviewed": True})
    assert client.get("/api/recipes-review").json()["recipes"] == []  # bewaard: een half jaar niet vragen

    client.patch(f"/api/recipes/{never.id}/flags", json={"archived": True})
    names = [r["name"] for r in client.get("/api/recipes").json()["recipes"]]
    assert names == ["Lasagne"]
    assert [r["name"] for r in client.get("/api/recipes?filter=archived").json()["recipes"]] == ["Vergeten soep"]
    assert "Vergeten soep" not in client.get("/recepten").text
    assert "Vergeten soep" in client.get("/recepten?filter=opgeruimd").text
    assert "Lasagne" in client.get("/recepten?filter=favorieten").text
    assert "Lekker?" in client.get(f"/recipe/{fav.id}/koken").text


def test_today_without_plan_shows_ideas(db):
    r = _recipe(db, "Snelle wraps", [])
    r.total_time, r.favorite = "20 minuten", True
    db.commit()
    page = TestClient(app).get("/").text
    assert "Nog niets voor vanavond" in page and "Snelle wraps" in page and "Iets uit de vriezer" in page


def test_feedback_one_vote_per_day_can_switch(db):
    r = _recipe(db, "Stamppot", [])
    client = TestClient(app)
    client.post(f"/api/recipes/{r.id}/feedback", json={"rating": "up"})
    again = client.post(f"/api/recipes/{r.id}/feedback", json={"rating": "up"}).json()
    assert again["thumbs_up"] == 1  # niet opnieuw tellen
    switched = client.post(f"/api/recipes/{r.id}/feedback", json={"rating": "down"}).json()
    assert switched["thumbs_up"] == 0 and switched["thumbs_down"] == 1 and switched["rating"] == "down"
