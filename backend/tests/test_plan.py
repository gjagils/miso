"""Planregels (recept / restje / voorraad), personen en schalen, vriezer, besteldag, migratie.

Geen echte AH-calls: zoeken en het lijstje vullen zijn gemockt.
"""
from datetime import date, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from app import planning
from app.api import plan as plan_api
from app.api import routes
from app.main import app
from app.matching import MATCH_VERSION
from app.migrations import migrate
from app.models import FreezerItem, PlanEntry, Recipe
from app.nutrition import analyze_week
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)


def _g(text, pid, grams, pack_g, qty=1):
    """Ingrediënt met vergelijkbare hoeveelheid (gram) en verpakking (gram)."""
    return {"text": text, "search": text, "skip": False, "quantity": qty, "match_v": MATCH_VERSION,
            "product": {"id": pid, "name": f"p{pid}", "unit_size": f"{pack_g} g"},
            "need": {"amount": grams, "unit": "g", "spoon": False}, "pack": {"amount": pack_g, "unit": "g"}}


def _recipe4(db, name, ingredients, servings="4 personen"):
    r = _recipe(db, name, ingredients)
    r.servings = servings
    db.commit()
    return r


def _qty(cart):
    return {i["product_id"]: i["quantity"] for i in cart}


def _future_monday():
    return routes.monday_of(date.today()) + timedelta(days=7)


def _fake_search(monkeypatch, catalog: dict[str, dict] | None = None):
    catalog = catalog or {}

    async def fake(q, size=10):
        for key, product in catalog.items():
            if key in q.lower():
                return [product]
        return []
    monkeypatch.setattr(routes.ah_client, "search_products", fake)


# ── Schalen ────────────────────────────────────────────────────────────


def test_recipe_servings_parsing():
    assert planning.recipe_servings(Recipe(name="a", servings="4 personen")) == 4
    assert planning.recipe_servings(Recipe(name="a", servings="2")) == 2
    assert planning.recipe_servings(Recipe(name="a", servings="4-6 pers.")) == 4
    assert planning.recipe_servings(Recipe(name="a", servings="")) == 4
    assert planning.recipe_servings(Recipe(name="a", servings="een gezin")) == 4
    assert planning.recipe_servings(None) == 4


def test_scale_quantity_rules():
    assert planning.scale_quantity(1, 1.5) == 2
    assert planning.scale_quantity(3, 1.25) == 3  # onder 1,5x: niet ophogen
    assert planning.scale_quantity(2, 0.5) == 2   # nooit verlagen zonder vergelijkbare hoeveelheid
    assert planning.scale_quantity(1, 2.0) == 2
    assert planning.scale_quantity(0, 0.25) == 1


def test_aggregate_cart_scales_by_persons(db):
    r = _recipe4(db, "Pasta", [_g("500 g pasta", 1, 500, 500), _g("300 g gehakt", 2, 300, 300), _ing("1 ui", 3)])
    assert _qty(routes.aggregate_cart([r])[0]) == {1: 1, 2: 1, 3: 1}
    # recept voor 4, gepland voor 6 -> 1,5x
    six = _qty(routes.aggregate_cart([r], [planning.scale_factor(6, r)])[0])
    assert six == {1: 2, 2: 2, 3: 2}
    # voor 2 -> 0,5x, maar minstens 1 verpakking
    two = _qty(routes.aggregate_cart([r], [planning.scale_factor(2, r)])[0])
    assert two == {1: 1, 2: 1, 3: 1}
    # recept voor 2 personen, gezin van 4 -> 2x
    small = _recipe4(db, "Klein", [_g("250 g rijst", 4, 250, 400)], servings="2")
    assert _qty(routes.aggregate_cart([small], [planning.scale_factor(4, small)])[0]) == {4: 2}


def test_aggregate_cart_extras_add_one_each(db):
    r = _recipe4(db, "Pasta", [_ing("pasta", 1)])
    cart, unmatched = routes.aggregate_cart([r], extras=[{"text": "pasta", "product": {"id": 1, "name": "p1"}},
                                                         {"text": "parmezaan", "product": {"id": 9, "name": "Parm"}},
                                                         {"text": "iets raars", "product": None}])
    assert _qty(cart) == {1: 2, 9: 1}
    assert unmatched == ["iets raars"]


# ── Planregels ─────────────────────────────────────────────────────────


def test_create_recipe_entry_with_persons_scales_week_cart(db):
    r = _recipe4(db, "Pasta", [_g("500 g pasta", 1, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    resp = client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id, "persons": 6}).json()
    assert resp["ok"] and len(resp["entries"]) == 1
    e = resp["entries"][0]
    assert e["entry_id"] and e["kind"] == "recipe" and e["persons"] == 6 and not e["persons_is_default"]
    assert e["recipe"]["name"] == "Pasta" and e["title"] == "Pasta"
    assert resp["status"]["missing"] == [{"name": "p1", "quantity": 2}]
    # zonder personen: huishoudgrootte (instelbaar)
    client.patch("/api/plan/settings", json={"household_size": 2})
    resp = client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=1)), "recipe_id": r.id}).json()
    assert resp["entries"][0]["persons"] == 2 and resp["entries"][0]["persons_is_default"]
    assert _qty(routes.week_cart(db, monday)[0]) == {1: 2}  # 750 g + 250 g = 1000 g = 2 pakken


def test_cook_double_tomorrow_creates_leftover_and_doubles_groceries(db):
    r = _recipe4(db, "Lasagne", [_g("500 g gehakt", 2, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    resp = client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id, "cook_double": "tomorrow"}).json()
    cook, rest = resp["entries"]
    assert cook["cook_double"] == "tomorrow" and cook["grocery_persons"] == 8
    assert rest["kind"] == "leftover" and rest["date"] == str(monday + timedelta(days=1))
    assert rest["title"] == "Rest van Lasagne" and rest["source_entry_id"] == cook["entry_id"]
    assert rest["grocery_persons"] == 0
    assert _qty(routes.week_cart(db, monday)[0]) == {2: 2}  # dubbel, het restje zelf kost niets

    week = client.get(f"/api/week?week={monday}").json()
    day1 = week["days"][1]
    assert day1["recipes"] == []  # oud veld: alleen gekookte recepten
    assert day1["entries"][0]["kind"] == "leftover"
    assert week["days"][0]["entries"][0]["leftover_entry_ids"] == [rest["entry_id"]]
    assert week["days"][0]["recipes"][0]["entry_id"] == cook["entry_id"]

    # restje weg -> niet meer dubbel inkopen
    assert client.delete(f"/api/plan/entries/{rest['entry_id']}").json()["ok"]
    assert db.get(PlanEntry, cook["entry_id"]).cook_double is None
    assert _qty(routes.week_cart(db, monday)[0]) == {2: 1}

    # kookdag weg -> restje gaat mee
    again = client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id, "cook_double": "tomorrow"}).json()
    ids = [e["entry_id"] for e in again["entries"]]
    out = client.delete(f"/api/plan/entries/{ids[0]}").json()
    assert sorted(out["deleted"]) == sorted(ids)


def test_cook_double_freezer_adds_freezer_item(db):
    r = _recipe4(db, "Chili", [_g("500 g bonen", 5, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    resp = client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id, "persons": 3,
                                                  "cook_double": "freezer"}).json()
    assert len(resp["entries"]) == 1
    assert resp["freezer_item"]["name"] == "Chili" and resp["freezer_item"]["portions"] == 3
    item = db.query(FreezerItem).one()
    assert item.from_recipe_id == r.id and item.added_on == str(monday)
    assert _qty(routes.week_cart(db, monday)[0]) == {5: 2}  # 6 personen / recept voor 4 = 750 g


def test_stock_entry_with_extras_and_freezer_suggestion(db, monkeypatch):
    _fake_search(monkeypatch, {"pasta": {"id": 11, "name": "AH Biologisch Pasta penne", "unit_size": "500 g"}})
    monday = _future_monday()
    client = TestClient(app)
    fz = client.post("/api/freezer", json={"name": "Pastasaus", "portions": 2}).json()["item"]
    assert client.get("/api/freezer").json()["items"][0]["name"] == "Pastasaus"

    resp = client.post("/api/plan/entries", json={"date": str(monday), "kind": "stock", "freezer_item_id": fz["id"],
                                                  "extras": ["pasta", "  ", "onvindbaar ding"]}).json()
    e = resp["entries"][0]
    assert e["kind"] == "stock" and e["title"] == "Pastasaus uit de vriezer" and e["recipe_id"] is None
    assert [x["text"] for x in e["extras"]] == ["pasta", "onvindbaar ding"]
    assert e["extras"][0]["product_id"] == 11 and e["extras"][1]["product_id"] is None
    assert resp["freezer_item"]["portions"] == 1
    cart, unmatched = routes.week_cart(db, monday)
    assert _qty(cart) == {11: 1} and unmatched == ["onvindbaar ding"]

    # laatste portie -> item weg
    client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=1)), "kind": "stock", "freezer_item_id": fz["id"]})
    assert client.get("/api/freezer").json()["items"] == []
    missing = client.post("/api/plan/entries", json={"date": str(monday), "kind": "stock", "freezer_item_id": fz["id"]})
    assert missing.status_code == 404

    # vrije tekst zonder vriezer; leeg mag niet
    ok = client.post("/api/plan/entries", json={"date": str(monday), "kind": "stock", "text": "Pannenkoeken"}).json()
    assert ok["entries"][0]["title"] == "Pannenkoeken" and ok["entries"][0]["extras"] == []
    assert client.post("/api/plan/entries", json={"date": str(monday), "kind": "stock"}).status_code == 400

    # extras wijzigen: bestaande koppeling blijft, nieuwe regel wordt gekoppeld
    pid = ok["entries"][0]["entry_id"]
    patched = client.patch(f"/api/plan/entries/{pid}", json={"extras": ["pasta"], "text": "Pannenkoeken met stroop"}).json()
    assert patched["entry"]["extras"][0]["product_id"] == 11 and patched["entry"]["text"] == "Pannenkoeken met stroop"


def test_move_and_update_entry(db):
    r = _recipe4(db, "Soep", [_ing("ui", 1)])
    monday = _future_monday()
    client = TestClient(app)
    cook, rest = client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id,
                                                        "cook_double": "tomorrow"}).json()["entries"]
    moved = client.patch(f"/api/plan/entries/{cook['entry_id']}", json={"date": str(monday + timedelta(days=3))}).json()
    assert moved["ok"] and moved["entry"]["date"] == str(monday + timedelta(days=3))
    assert db.get(PlanEntry, rest["entry_id"]).date == str(monday + timedelta(days=4))  # restje schuift mee
    p = client.patch(f"/api/plan/entries/{cook['entry_id']}", json={"persons": 5}).json()
    assert p["entry"]["persons"] == 5 and db.get(PlanEntry, rest["entry_id"]).persons == 5
    p = client.patch(f"/api/plan/entries/{cook['entry_id']}", json={"persons": None}).json()
    assert p["entry"]["persons_is_default"] and p["entry"]["persons"] == 4
    assert client.patch(f"/api/plan/entries/{cook['entry_id']}", json={"date": "gisteren"}).status_code == 400
    assert client.patch("/api/plan/entries/9999", json={"date": str(monday)}).status_code == 404
    assert client.delete("/api/plan/entries/9999").status_code == 404
    assert client.patch(f"/api/plan/entries/{cook['entry_id']}", json={"extras": ["x"]}).status_code == 400


def test_create_entry_validation(db):
    client = TestClient(app)
    assert client.post("/api/plan/entries", json={"date": "2026-13-01", "recipe_id": 1}).status_code == 400
    assert client.post("/api/plan/entries", json={"date": "2026-10-12", "recipe_id": 999}).status_code == 404
    assert client.post("/api/plan/entries", json={"date": "2026-10-12", "kind": "soep"}).status_code == 422
    assert client.post("/api/plan/entries", json={"date": "2026-10-12", "recipe_id": 1, "persons": 0}).status_code == 422


def test_list_entries_range(db):
    r = _recipe4(db, "Soep", [_ing("ui", 1)])
    monday = _future_monday()
    client = TestClient(app)
    for i in (0, 2, 9):
        client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=i)), "recipe_id": r.id})
    got = client.get(f"/api/plan/entries?start={monday}&days=7").json()
    assert [e["date"] for e in got["entries"]] == [str(monday), str(monday + timedelta(days=2))]
    assert got["household_size"] == 4
    assert len(client.get(f"/api/plan/entries?week={monday + timedelta(days=8)}").json()["entries"]) == 1


def test_old_plan_api_keeps_new_entry_kinds(db):
    a = _recipe4(db, "A", [_ing("ui", 1)])
    b = _recipe4(db, "B", [_ing("rijst", 2)])
    monday = _future_monday()
    day = str(monday)
    client = TestClient(app)
    cook = client.post("/api/plan/entries", json={"date": day, "recipe_id": a.id, "persons": 6,
                                                  "cook_double": "tomorrow"}).json()["entries"][0]
    client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=2)), "kind": "stock", "text": "Soep"})
    # oude app stuurt de recepten per dag terug (zoals uit /api/week) + een extra recept
    week = client.get(f"/api/week?week={day}").json()
    days = {d["date"]: [r["id"] for r in d["recipes"]] for d in week["days"]}
    days[str(monday + timedelta(days=3))].append(b.id)
    assert client.post("/api/plan", json={"week": day, "days": days}).json()["ok"]
    kinds = sorted((e.date, e.kind) for e in db.query(PlanEntry).all())
    assert kinds == [(day, "recipe"), (str(monday + timedelta(days=1)), "leftover"),
                     (str(monday + timedelta(days=2)), "stock"), (str(monday + timedelta(days=3)), "recipe")]
    assert db.get(PlanEntry, cook["entry_id"]).persons == 6  # zelfde regel, personen behouden
    # recept weghalen via oude API: restje gaat mee, voorraad blijft
    days[day] = []
    client.post("/api/plan", json={"week": day, "days": days})
    assert sorted(e.kind for e in db.query(PlanEntry).all()) == ["recipe", "stock"]


def test_list_link_and_basket_take_persons(db, monkeypatch):
    r = _recipe4(db, "Pasta", [_g("500 g pasta", 5, 500, 500)])
    client = TestClient(app)
    link = client.post("/api/list-link", json={"recipe_ids": [r.id], "persons": {str(r.id): 8}}).json()
    assert "p=5%3A2" in link["url"]
    link = client.post("/api/list-link", json={"recipe_ids": [r.id]}).json()
    assert "p=5%3A1" in link["url"]
    monday = _future_monday()
    client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id, "persons": 12})
    assert "p=5%3A3" in client.post("/api/list-link", json={"week": str(monday)}).json()["url"]


def test_sync_pushes_scaled_quantities_and_extras(db, monkeypatch):
    _fake_search(monkeypatch, {"stroop": {"id": 77, "name": "Stroop", "unit_size": "450 g"}})
    r = _recipe4(db, "Pasta", [_g("500 g pasta", 5, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id, "persons": 8})
    # extra zonder product (AH was even weg) wordt bij het bijwerken alsnog gekoppeld
    db.add(PlanEntry(date=str(monday + timedelta(days=1)), kind="stock", recipe_id=0, text="Pannenkoeken",
                     extras_json='[{"text": "stroop", "product": null}]'))
    db.commit()
    routes._set_setting(db, "ah_refresh_token", "x")
    sent = []

    async def fake_add(items):
        sent.extend(items)

    async def no_match(*args, **kwargs):
        return 0
    monkeypatch.setattr(routes.ah_client, "add_to_cart", fake_add)
    monkeypatch.setattr(routes, "_automatch", no_match)
    out = client.post("/api/plan/sync", json={"week": str(monday)}).json()
    assert out["ok"] and out["added"] == 2
    assert sorted((i["product_id"], i["quantity"]) for i in sent) == [(5, 2), (77, 1)]
    assert out["status"]["missing_count"] == 0 and out["status"]["on_list"] == 2


# ── Volgende week / besteldag / instellingen ──────────────────────────


def test_next_week_status(db):
    r = _recipe4(db, "Soep", [_ing("ui", 1)])
    client = TestClient(app)
    thursday = date(2026, 10, 8)  # donderdag
    nxt = date(2026, 10, 12)
    for i in range(4):
        db.add(PlanEntry(date=str(nxt + timedelta(days=i)), recipe_id=r.id, kind="recipe"))
    db.commit()
    s = plan_api.next_week_status(db, today=thursday)
    assert s["order_day"] == 6 and s["days_until_order"] == 3 and s["week"] == "2026-10-12"
    assert s["planned_days"] == 4 and s["total_days"] == 7 and not s["prominent"]
    assert s["missing_dates"] == ["2026-10-16", "2026-10-17", "2026-10-18"]
    assert s["list_status"]["missing_count"] == 1 and s["list_status"]["needed"] == 1
    assert s["message"] == "Volgende week: 4 van 7 dagen gepland · nog 3 dagen tot zondag (besteldag)"
    friday = plan_api.next_week_status(db, today=date(2026, 10, 9))
    assert friday["days_until_order"] == 2 and friday["prominent"]
    assert "morgen is het zondag" in plan_api.next_week_status(db, today=date(2026, 10, 10))["message"]
    assert "vandaag is het zondag" in plan_api.next_week_status(db, today=date(2026, 10, 11))["message"]

    client.patch("/api/plan/settings", json={"order_weekday": 4})
    assert plan_api.next_week_status(db, today=thursday)["days_until_order"] == 1
    live = client.get("/api/plan/next-week-status").json()
    assert live["ok"] and live["total_days"] == 7 and "list_status" in live and live["order_day"] == 4


def test_plan_settings_api_and_form(db):
    client = TestClient(app)
    assert client.get("/api/plan/settings").json() == {"ok": True, "household_size": 4, "order_weekday": 6,
                                                       "order_weekday_name": "zondag"}
    got = client.patch("/api/plan/settings", json={"household_size": 5, "order_weekday": 0}).json()
    assert got["household_size"] == 5 and got["order_weekday_name"] == "maandag"
    assert client.patch("/api/plan/settings", json={"household_size": 0}).status_code == 422
    page = client.post("/settings/plan", data={"household_size": "3", "order_weekday": "5"})
    assert page.status_code == 200 and "Opgeslagen." in page.text
    assert planning.household_size(db) == 3 and planning.order_weekday(db) == 5
    assert "Gezin en besteldag" in client.get("/settings").text


def test_freezer_crud(db):
    client = TestClient(app)
    item = client.post("/api/freezer", json={"name": " Soep ", "portions": 3}).json()["item"]
    assert item["name"] == "Soep" and item["added_on"] == str(date.today())
    assert client.patch(f"/api/freezer/{item['id']}", json={"portions": 1, "name": "Erwtensoep"}).json()["item"]["name"] == "Erwtensoep"
    assert client.patch(f"/api/freezer/{item['id']}", json={"portions": 0}).json()["deleted"]
    assert client.get("/api/freezer").json()["items"] == []
    assert client.delete(f"/api/freezer/{item['id']}").status_code == 404
    assert client.post("/api/freezer", json={"name": ""}).status_code == 422
    other = client.post("/api/freezer", json={"name": "Stoof"}).json()["item"]
    assert client.delete(f"/api/freezer/{other['id']}").json()["ok"]


# ── Gezondheid ─────────────────────────────────────────────────────────


def _prof(eiwit="vlees", basis="pasta"):
    return {"kcal": 600, "groente_g": 200, "eiwit": eiwit, "basis": basis, "keuken": "italiaans", "volkoren": False,
            "schijf": {"groente_fruit": True, "zetmeel": True, "eiwit": True, "zuivel": False, "vetten": True},
            "score": 4, "toelichting": ""}


def test_analyze_week_counts_leftovers_as_days_not_variety():
    a = analyze_week([("2026-10-12", _prof()), ("2026-10-14", _prof("vis", "rijst"))], leftover_days=2)
    assert a["dagen"] == 4 and a["restjes"] == 2 and a["eiwit"] == {"vis": 1, "vlees": 1}
    assert analyze_week([], leftover_days=1)["dagen"] == 1


def test_week_health_ignores_leftover_and_stock(db):
    from app.nutrition import save_profile

    r = _recipe4(db, "Pasta", [_ing("pasta", 1)])
    save_profile(db, r.id, _prof())
    monday = _future_monday()
    client = TestClient(app)
    client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r.id, "cook_double": "tomorrow"})
    client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=2)), "kind": "stock", "text": "Soep"})
    h = client.get(f"/api/week/health?week={monday}").json()
    assert h["dagen"] == 2 and h["restjes"] == 1 and h["eiwit"] == {"vlees": 1}
    assert len(h["recepten"]) == 1 and h["recepten"][0]["entry_id"]


# ── Pagina's ───────────────────────────────────────────────────────────


def test_pages_render_with_all_entry_kinds(db):
    r = _recipe4(db, "Lasagne", [_ing("gehakt", 1)])
    client = TestClient(app)
    today = date.today()
    client.post("/api/plan/entries", json={"date": str(today), "recipe_id": r.id, "cook_double": "tomorrow"})
    client.post("/api/plan/entries", json={"date": str(today), "kind": "stock", "text": "Soep <uit> de vriezer"})
    home = client.get("/").text
    assert "Lasagne" in home and "Soep &lt;uit&gt; de vriezer" in home and "Volgende week:" in home
    week = client.get("/weekmenu").text
    assert "Volgende week:" in week and "/static/plan.js" in week and "Vriezer" in week
    assert "Weekmenu vastzetten" not in week and "Controleer en vul aan" not in week
    assert "Plan volgende week" in week and "/kiezen?week=next" in week
    detail = client.get(f"/recipe/{r.id}").text
    assert 'id="plan-btn"' in detail and "/static/plan.js" in detail
    assert "/static/plan.js" in client.get("/kiezen?week=next").text
    assert client.get("/static/plan.js").status_code == 200


def test_parse_week_next():
    assert routes.parse_week("next") == routes.monday_of(date.today()) + timedelta(days=7)


# ── Migratie ───────────────────────────────────────────────────────────


def test_migration_adds_missing_columns_idempotently(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'old.db'}")
    with engine.begin() as conn:  # schema zoals in productie vóór deze wijziging
        conn.execute(text("CREATE TABLE plan_entries (id INTEGER NOT NULL PRIMARY KEY, date VARCHAR(10) NOT NULL, "
                          "recipe_id INTEGER NOT NULL)"))
        conn.execute(text("INSERT INTO plan_entries (date, recipe_id) VALUES ('2026-10-12', 3)"))
    added = migrate(engine)
    assert set(added) == {f"plan_entries.{c}" for c in ("kind", "persons", "text", "extras_json",
                                                        "source_entry_id", "cook_double", "freezer_name")}
    assert migrate(engine) == []  # tweede keer: niets te doen
    with engine.connect() as conn:
        row = conn.execute(text("SELECT kind, persons, text, extras_json, cook_double FROM plan_entries")).one()
    assert tuple(row) == ("recipe", None, "", "[]", None)
    # het model werkt op de gemigreerde tabel
    from sqlalchemy.orm import Session

    from app.database import Base
    Base.metadata.create_all(engine)  # maakt alleen nieuwe tabellen (freezer_items)
    with Session(engine) as s:
        e = s.query(PlanEntry).one()
        assert e.kind == "recipe" and e.extras == []
        s.add(PlanEntry(date="2026-10-13", kind="stock", recipe_id=0, text="Soep"))
        s.add(FreezerItem(name="Soep", portions=2, added_on="2026-10-12"))
        s.commit()


def test_deleting_freezer_stock_day_puts_portion_back(db, monkeypatch):
    _fake_search(monkeypatch)
    client = TestClient(app)
    item = client.post("/api/freezer", json={"name": "Pastasaus", "portions": 1}).json()["item"]
    day = str(_future_monday())
    r = client.post("/api/plan/entries", json={"date": day, "kind": "stock", "freezer_item_id": item["id"]}).json()
    assert r["ok"] and client.get("/api/freezer").json()["items"] == []  # laatste portie gebruikt
    entry_id = r["entries"][0]["entry_id"]
    assert client.delete(f"/api/plan/entries/{entry_id}").json()["ok"]
    items = client.get("/api/freezer").json()["items"]
    assert [(i["name"], i["portions"]) for i in items] == [("Pastasaus", 1)]
