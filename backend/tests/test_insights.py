"""Kosten van recept en week, uitgaven per week, waarschijnlijk op (herbestel-voorspelling)."""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app import ah_sync, replenish
from app.api import routes
from app.main import app
from app.models import AHPrice, AHTrip, PlanEntry
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)

TODAY = date.today()
D = lambda n: str(TODAY - timedelta(days=n))  # noqa: E731


def _trip(db, source, ext, day, lines, total=None, discount=None):  # noqa: F811
    t = AHTrip(source=source, external_id=str(ext), date=day, total=total, discount=discount)
    t.lines = [{"product_id": pid, "name": name, "quantity": qty, "unit_price": 1.0, "amount": qty, "bonus": False,
                "category": ""} for pid, name, qty in lines]
    db.add(t)
    db.commit()
    return t


# ── Kosten ─────────────────────────────────────────────────────────────


def test_recipe_and_week_cost_with_bonus_and_snapshot(db):  # noqa: F811
    r = _recipe(db, "Pasta", [_ing("pasta", 5, qty=2), _ing("kaas", 6), _ing("ui", 7), _ing("zout", skip=True)])
    ings = r.ingredients
    ings[0]["product"]["price"] = "1.50"   # 2 pakken
    ings[1]["product"]["price"] = ""       # geen prijs bij de koppeling: uit het snapshot
    ings[2]["product"]["price"] = "0.80"
    r.ingredients = ings
    r.servings = "4 personen"
    db.commit()
    db.add(AHPrice(product_id=6, date=D(10), price=2.0))
    db.add(AHPrice(product_id=6, date=D(1), price=2.5))  # laatste snapshot wint
    db.commit()
    ah_sync.record_bonus(db, {"start": str(routes.monday_of(TODAY)), "end": str(routes.monday_of(TODAY) + timedelta(days=6)),
                              "products": {7: {"id": 7, "title": "Ui", "now": 0.5, "was": 0.8,
                                               "saving": 0.3, "mechanism": "bonus"}}, "personal": 0, "groups": 0}, False)

    client = TestClient(app)
    cost = client.get(f"/api/recipes/{r.id}/cost").json()
    assert cost["ok"] and cost["total"] == 6.0  # 2x1,50 + 2,50 + 0,50 (bonus)
    assert cost["bonus_saving"] == 0.3 and cost["per_person"] == 1.5 and cost["persons"] == 4 and cost["complete"]
    by = {ln["product_id"]: ln for ln in cost["lines"]}
    assert by[7]["bonus"] and by[7]["price"] == 0.5 and by[6]["price"] == 2.5 and not by[6]["bonus"]
    # Voor 8 personen: verpakkingen zonder vergelijkbare hoeveelheid verdubbelen (factor 2)
    assert client.get(f"/api/recipes/{r.id}/cost?persons=8").json()["total"] == 12.0
    assert client.get("/api/recipes/999/cost").status_code == 404

    monday = routes.monday_of(TODAY) + timedelta(days=7)
    db.add(PlanEntry(date=str(monday), recipe_id=r.id, kind="recipe"))
    db.add(PlanEntry(date=str(monday + timedelta(days=1)), recipe_id=r.id, kind="leftover"))
    db.commit()
    week = client.get(f"/api/week/cost?week={monday}").json()
    # volgende week: de bonus van deze week geldt daar niet, dus ui tegen de gewone prijs (0,80)
    assert week["total"] == 6.3 and week["meals"] == 8 and week["per_meal"] == 0.79 and week["bonus_period"] is None
    assert week["unknown"] == [] and week["known_count"] == 3


def test_cost_reports_unknown_prices(db):  # noqa: F811
    r = _recipe(db, "X", [_ing("iets", 9), _ing("open")])
    ings = r.ingredients
    ings[0]["product"]["price"] = ""
    r.ingredients = ings
    db.commit()
    cost = TestClient(app).get(f"/api/recipes/{r.id}/cost").json()
    assert cost["total"] == 0 and cost["unknown"] == ["p9"] and cost["unmatched"] == ["open"]
    assert cost["per_person"] is None and not cost["complete"]


# ── Uitgaven ───────────────────────────────────────────────────────────


def test_spend_per_week(db):  # noqa: F811
    monday = routes.monday_of(TODAY)
    _trip(db, "bestelling", 1, str(monday), [(10, "Melk", 1)], total=60.0, discount=5.0)
    _trip(db, "kassabon", "a", str(monday + timedelta(days=min(2, 6 - monday.weekday()))), [(10, "Melk", 1)], total=12.5)
    _trip(db, "kassabon", "b", str(monday - timedelta(days=7)), [(11, "Brood", 1)], total=8.0)
    _trip(db, "kassabon", "c", str(monday - timedelta(days=14)), [(11, "Brood", 1)])  # zonder bedrag
    resp = TestClient(app).get(f"/api/spend?weeks=3&detail={monday}").json()
    assert resp["ok"] and [w["total"] for w in resp["weeks"]] == [0.0, 8.0, 72.5]
    d = resp["detail"]
    assert d["week"] == str(monday) and len(d["trips"]) == 2
    assert d["top"][0] == {"product_id": 10, "name": "Melk", "quantity": 2.0, "amount": 2.0, "bonus": False}
    assert d["categories"] == [{"category": "Overig", "amount": 2.0}]
    assert resp["weeks"][2]["discount"] == 5.0 and resp["weeks"][2]["trips"] == 2 and resp["weeks"][0]["unknown"] == 1
    assert resp["average_week"] == 40.25 and resp["average_per_person_day"] == round(40.25 / 4 / 7, 2)


# ── Waarschijnlijk op ──────────────────────────────────────────────────


def test_predict_replenishment():
    trips = [{"source": "bestelling", "date": D(n), "lines": [{"product_id": 1, "name": "WC-papier", "quantity": 1}]}
             for n in (70, 35, 0)]  # elke 5 weken, net gekocht
    trips += [{"source": "kassabon", "date": D(n), "lines": [{"product_id": 2, "name": "MELK", "quantity": 2}]}
              for n in (21, 14, 7)]  # wekelijks, laatste week geleden -> nu aan de beurt
    trips += [{"source": "kassabon", "date": D(n), "lines": [{"product_id": 3, "name": "Kaarsen", "quantity": 1}]}
              for n in (300, 150, 0)]  # te onregelmatig (>120 dagen)
    trips += [{"source": "kassabon", "date": D(3), "lines": [{"product_id": 4, "name": "Eenmalig", "quantity": 1}]}]
    rows = replenish.predict(trips, today=TODAY)
    by = {r["product_id"]: r for r in rows}
    assert set(by) == {1, 2}
    assert by[2]["status"] == "op" and by[2]["interval_days"] == 7 and by[2]["days_left"] == 0 and by[2]["avg_quantity"] == 2
    assert by[1]["status"] == "ok" and by[1]["interval_days"] == 35 and by[1]["due_on"] == str(TODAY + timedelta(days=35))
    assert rows[0]["product_id"] == 2  # meest urgent eerst
    # Binnenkort: wc-papier 30 dagen geleden gekocht -> over 5 dagen aan de beurt
    trips2 = [{"source": "bestelling", "date": D(n), "lines": [{"product_id": 1, "name": "WC-papier", "quantity": 1}]}
              for n in (100, 65, 30)]
    assert replenish.predict(trips2, today=TODAY)[0]["status"] == "binnenkort"
    # "Hebben we nog" schuift de voorspelling op
    snoozed = replenish.predict(trips, today=TODAY, snooze={2: str(TODAY + timedelta(days=10))})
    assert snoozed[0]["product_id"] == 2 and snoozed[0]["status"] == "ok" and snoozed[0]["snoozed_until"]
    assert replenish.predict(trips, today=TODAY, exclude={2}) == [by[1]]


def test_replenish_endpoint_excludes_week_cart_and_snoozes(db):  # noqa: F811
    for n in (21, 14, 7):
        _trip(db, "kassabon", f"m{n}", D(n), [(10, "Melk", 1), (5, "Pasta", 1)])
    r = _recipe(db, "Pasta", [_ing("pasta", 5)])
    monday = routes.monday_of(TODAY)
    db.add(PlanEntry(date=str(monday), recipe_id=r.id, kind="recipe"))
    db.commit()
    client = TestClient(app)
    resp = client.get(f"/api/replenish?week={monday}").json()
    assert resp["ok"] and resp["trips"] == 3 and [d["product_id"] for d in resp["due"]] == [10]  # pasta zit al in de week
    assert client.post("/api/replenish/snooze", json={"product_id": 10, "days": 14}).json()["snoozed_until"] == str(TODAY + timedelta(days=14))
    resp = client.get(f"/api/replenish?week={monday}").json()
    assert resp["due"] == [] and resp["later"][0]["product_id"] == 10


# ── Weekbudget, kooktijd per weekdag, basisvoorraad, "dit is op" ───────


def test_week_budget_in_settings_and_cost(db):  # noqa: F811
    client = TestClient(app)
    assert client.get("/api/plan/settings").json()["week_budget"] == 0
    assert client.patch("/api/plan/settings", json={"week_budget": 120}).json()["week_budget"] == 120
    assert client.patch("/api/plan/settings", json={"week_budget": -5}).status_code == 422

    r = _recipe(db, "Pasta", [_ing("pasta", 5, qty=2)])
    ings = r.ingredients
    ings[0]["product"]["price"] = "30.00"
    r.ingredients = ings
    db.commit()
    monday = routes.monday_of(TODAY) + timedelta(days=7)
    db.add(PlanEntry(date=str(monday), recipe_id=r.id, kind="recipe"))
    db.commit()
    c = client.get(f"/api/week/cost?week={monday}").json()
    assert c["total"] == 60.0 and c["budget"] == 120 and c["budget_pct"] == 50
    assert c["actual"] is None and c["actual_pct"] is None
    _trip(db, "bestelling", 1, str(monday + timedelta(days=2)), [(5, "Pasta", 2)], total=90.0)
    c = client.get(f"/api/week/cost?week={monday}").json()
    assert c["actual"] == 90.0 and c["actual_pct"] == 75
    client.patch("/api/plan/settings", json={"week_budget": 0})
    c = client.get(f"/api/week/cost?week={monday}").json()
    assert c["budget"] is None and c["budget_pct"] is None

    # webformulier bewaart het ook
    resp = client.post("/settings/plan", data={"household_size": 4, "order_weekday": 6, "week_budget": 150})
    assert resp.status_code == 200 and client.get("/api/plan/settings").json()["week_budget"] == 150
    assert "9999" in client.post("/settings/plan", data={"household_size": 4, "order_weekday": 6, "week_budget": 99999}).text


def test_cooktime_fits_the_weekday():
    from app.cooktime import minutes, time_fit

    assert minutes("45 min") == 45 and minutes("1 uur") == 60 and minutes("1,5 uur") == 90 and minutes("") is None
    monday, friday, saturday = "2026-10-12", "2026-10-16", "2026-10-17"
    assert time_fit("20 min", monday) == (4.0, "snel klaar")
    assert time_fit("30 min", monday)[0] == 4.0 and time_fit("45 min", monday)[0] == 0.0
    assert time_fit("1 uur", monday) == (-7.5, "duurt 60 min, lang voor doordeweeks")
    assert time_fit("3 uur", monday)[0] == -20.0  # maximale straf
    assert time_fit("1 uur", friday)[0] == 0.0 and time_fit("15 min", friday)[0] == 0.0  # vrijdag neutraal
    assert time_fit("1 uur", saturday) == (4.0, "heeft tijd in het weekend") and time_fit("20 min", saturday)[0] == 0.0
    assert time_fit("onbekend", monday) == (0.0, "")


def test_pantry_items_need_two_purchases_and_are_flagged():
    from app import replenish

    trips = [{"source": "kassabon", "date": D(n), "lines": [{"product_id": 7, "name": "AH Olijfolie extra vergine", "quantity": 1},
                                                           {"product_id": 8, "name": "AH Chips", "quantity": 1}]} for n in (60, 30)]
    assert replenish.predict(trips, today=TODAY) == []  # twee keer is te weinig zonder basisvoorraad
    rows = replenish.predict(trips, today=TODAY, pantry={"olijfolie", "bloem"})
    assert [r["product_id"] for r in rows] == [7] and rows[0]["basis"] is True and rows[0]["status"] == "op"
    assert replenish.is_pantry("AH Bloem", {"bloem"}) and not replenish.is_pantry("AH Chips", {"bloem"})


def test_pantry_terms_from_skipped_ingredients(db):  # noqa: F811
    from app import replenish

    r = _recipe(db, "Soep", [_ing("2 el olijfolie", None), _ing("zout"), _ing("ui", 3)])
    ings = r.ingredients
    for i in ings[:2]:
        i["auto_skip"] = True
    r.ingredients = ings
    db.commit()
    terms = replenish.pantry_terms([r])
    assert "olijfolie" in terms and "zout" in terms and "uien" not in terms


def test_replenish_endpoint_flags_pantry_and_out_button(db, monkeypatch):  # noqa: F811
    from app.api import ah_data as ahapi
    from app.api import shopping

    r = _recipe(db, "Soep", [_ing("olijfolie", None)])
    ings = r.ingredients
    ings[0]["auto_skip"] = True
    r.ingredients = ings
    db.commit()
    for n in (70, 35):
        _trip(db, "kassabon", f"o{n}", D(n), [(7, "AH Olijfolie", 1)])
    client = TestClient(app)
    due = client.get("/api/replenish").json()["due"]
    assert [d["product_id"] for d in due] == [7] and due[0]["basis"] is True

    # "Dit is op": zonder AH-koppeling een nette melding, met koppeling op het lijstje + rust voor de voorspelling
    assert client.post("/api/replenish/out", json={"product_id": 7, "name": "Olijfolie"}).json()["ok"] is False
    pushed = []

    async def fake_put(list_ids, products):
        pushed.append(products)
        return {"ok": True, "added": len(products)}
    monkeypatch.setattr(shopping, "_use_user_tokens", lambda _db: True)
    monkeypatch.setattr(ahapi, "_put_on_list", fake_put)
    resp = client.post("/api/replenish/out", json={"product_id": 7, "name": "Olijfolie", "quantity": 2}).json()
    assert resp["ok"] and pushed == [[{"product_id": 7, "name": "Olijfolie", "quantity": 2}]]
    assert client.get("/api/replenish").json()["due"] == []  # even met rust gelaten


def test_kids_cannot_press_out_or_sync(db, monkeypatch):  # noqa: F811
    from sqlalchemy.orm import sessionmaker

    from app import database
    from app.api import family

    factory = sessionmaker(bind=db.get_bind())  # zelfde (in-memory) database als de test
    monkeypatch.setattr(database, "SessionLocal", factory)
    monkeypatch.setattr(family, "SessionLocal", factory)
    client = TestClient(app, headers={"X-Miso-Member": "hannah"})
    for path in ("/api/replenish/out", "/api/replenish/snooze", "/api/ah/sync"):
        assert client.post(path, json={"product_id": 1}).status_code == 403, path


# ── Goedkoper alternatief (B4) ─────────────────────────────────────────


def _kip_recipe(db, price="6.00", manual=False):  # noqa: F811
    r = _recipe(db, "Kip", [_ing("500 g kipfilet", 1), _ing("zout", skip=True)])
    ings = r.ingredients
    ings[0]["product"].update(name="A-merk kipfilet", price=price, unit_size="500 g")
    ings[0]["manual"] = manual
    r.ingredients = ings
    db.commit()
    return r


def test_cheaper_suggests_same_product_for_less(db, monkeypatch):  # noqa: F811
    r = _kip_recipe(db)
    searched = []

    async def fake_search(q, size=10):
        searched.append(q)
        return [
            {"id": 1, "name": "A-merk kipfilet", "unit_size": "500 g", "price": "6.00", "brand": "Merk", "available": True},
            {"id": 2, "name": "AH Kipfilet", "unit_size": "500 g", "price": "4.50", "brand": "AH", "available": True,
             "category": "Vlees"},
            {"id": 3, "name": "AH Kipfilet bio", "unit_size": "500 g", "price": "5.90", "brand": "AH", "available": True},
            {"id": 4, "name": "AH Kippendij", "unit_size": "500 g", "price": "2.00", "brand": "AH", "available": True},
            {"id": 5, "name": "AH Kipfilet", "unit_size": "500 g", "price": "3.00", "brand": "AH", "available": False},
            {"id": 6, "name": "AH Kipfilet reepjes", "unit_size": "500 g", "price": "", "brand": "AH", "available": True},
        ]
    monkeypatch.setattr(routes.ah_client, "search_products", fake_search)
    resp = TestClient(app).post(f"/api/recipes/{r.id}/cheaper").json()
    assert resp["ok"] and len(resp["suggestions"]) == 1 and resp["total_saving"] == 1.5
    s = resp["suggestions"][0]
    assert s["index"] == 0 and s["text"] == "500 g kipfilet" and s["manual"] is False
    assert s["current"]["id"] == 1 and s["current"]["cost"] == 6.0
    assert s["alternative"]["id"] == 2 and s["alternative"]["cost"] == 4.5 and s["saving"] == 1.5
    assert s["alternative"]["name"] == "AH Kipfilet" and s["alternative"]["unit_size"] == "500 g"  # klaar om te kiezen
    assert searched  # er is echt gezocht
    assert TestClient(app).post("/api/recipes/999/cheaper").status_code == 404


def test_cheaper_ignores_small_savings_and_other_products(db, monkeypatch):  # noqa: F811
    r = _kip_recipe(db, price="4.60")

    async def fake_search(q, size=10):
        return [{"id": 2, "name": "AH Kipfilet", "unit_size": "500 g", "price": "4.50", "available": True},  # maar 10 cent
                {"id": 4, "name": "AH Kippendij", "unit_size": "500 g", "price": "1.00", "available": True}]  # ander product
    monkeypatch.setattr(routes.ah_client, "search_products", fake_search)
    resp = TestClient(app).post(f"/api/recipes/{r.id}/cheaper").json()
    assert resp["ok"] and resp["suggestions"] == [] and resp["total_saving"] == 0


def test_cheaper_counts_packs_not_just_price(db, monkeypatch):  # noqa: F811
    """Een goedkoper pak dat te klein is, is niet goedkoper: 2 kleine pakken kosten meer dan 1 groot."""
    r = _kip_recipe(db, price="6.00")

    async def fake_search(q, size=10):
        return [{"id": 2, "name": "AH Kipfilet", "unit_size": "250 g", "price": "3.50", "available": True}]  # 2 x 3,50 = 7,00
    monkeypatch.setattr(routes.ah_client, "search_products", fake_search)
    resp = TestClient(app).post(f"/api/recipes/{r.id}/cheaper").json()
    assert resp["suggestions"] == []


def test_kids_cannot_search_cheaper(db, monkeypatch):  # noqa: F811
    from sqlalchemy.orm import sessionmaker

    from app import database
    from app.api import family

    factory = sessionmaker(bind=db.get_bind())
    monkeypatch.setattr(database, "SessionLocal", factory)
    monkeypatch.setattr(family, "SessionLocal", factory)
    r = _kip_recipe(db)
    assert TestClient(app, headers={"X-Miso-Member": "hannah"}).post(f"/api/recipes/{r.id}/cheaper").status_code == 403


def test_cheaper_says_so_when_ah_gives_nothing(db, monkeypatch):  # noqa: F811
    """AH offline: niet "al een goede keuze" zeggen, maar dat er geen antwoord kwam."""
    r = _kip_recipe(db)

    async def fake_search(q, size=10):
        raise RuntimeError("AH is offline")
    monkeypatch.setattr(routes.ah_client, "search_products", fake_search)
    resp = TestClient(app).post(f"/api/recipes/{r.id}/cheaper").json()
    assert resp["ok"] is False and resp["unreachable"] is True and resp["suggestions"] == []
    assert "geen antwoord" in resp["error"]

    async def fake_empty(q, size=10):
        return []
    monkeypatch.setattr(routes.ah_client, "search_products", fake_empty)
    assert TestClient(app).post(f"/api/recipes/{r.id}/cheaper").json()["unreachable"] is True  # leeg = ook geen antwoord

    # Eén ingrediënt zonder resultaat tussen andere die wel antwoord gaven telt niet als onbereikbaar
    r2 = _recipe(db, "Mix", [_ing("500 g kipfilet", 1), _ing("500 g gehakt", 2)])
    ings = r2.ingredients
    for i in ings:
        i["product"].update(price="6.00", unit_size="500 g")
    r2.ingredients = ings
    db.commit()

    async def partial(q, size=10):
        return [{"id": 9, "name": "AH Kipfilet", "unit_size": "500 g", "price": "4.00", "available": True}] if "kip" in q else []
    monkeypatch.setattr(routes.ah_client, "search_products", partial)
    resp = TestClient(app).post(f"/api/recipes/{r2.id}/cheaper").json()
    assert resp["ok"] and resp["unreachable"] is False and len(resp["suggestions"]) == 1
