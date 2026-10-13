"""Koken met wat er is (F11): recepten die passen bij de vriezer en de laatst gekochte producten."""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app import cookwith
from app.main import app
from app.models import FreezerItem, PlanEntry
from tests.test_insights import D, _trip
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)


def test_terms_of_drops_brand_and_noise():
    assert cookwith.terms_of("AH Biologisch Courgette") == {"courgette"}
    assert cookwith.terms_of("AH Verse kipfilet 500 g") == {"kipfilet"}
    assert cookwith.terms_of("") == set()


def test_suggests_recipe_matching_freezer_and_recent_purchases(db):  # noqa: F811
    r = _recipe(db, "Courgette met gehakt", [_ing("500 g gehakt", 1), _ing("1 courgette", 2), _ing("1 ui", 3),
                                           _ing("zout", skip=True)])
    other = _recipe(db, "Sushi", [_ing("rijst voor sushi", 4), _ing("nori", 5)])
    db.add(FreezerItem(name="Gehakt", portions=2, added_on=str(date.today())))
    db.commit()
    _trip(db, "order", 1, D(1), [(9, "AH Biologisch Courgette", 1), (10, "AH Halfvolle melk", 1)])
    out = TestClient(app).get("/api/cook-with").json()
    assert out["ok"]
    names = [s["name"] for s in out["suggestions"]]
    assert names == ["Courgette met gehakt"] and other.name not in names
    s = out["suggestions"][0]
    assert s["covered"] == 2 and s["total"] == 3 and s["missing_count"] == 1
    assert {(m["source"], m["from"]) for m in s["matches"]} == {("vriezer", "Gehakt"), ("gekocht", "AH Biologisch Courgette")}
    assert out["inventory"]["freezer"] == ["Gehakt"]
    assert out["inventory"]["bought"][0]["name"] in ("AH Biologisch Courgette", "AH Halfvolle melk")


def test_old_purchases_planned_and_one_match_are_ignored(db):  # noqa: F811
    r = _recipe(db, "Courgette met gehakt", [_ing("500 g gehakt", 1), _ing("1 courgette", 2), _ing("1 ui", 3)])
    db.add(FreezerItem(name="Gehakt", portions=1, added_on=str(date.today())))
    db.commit()
    _trip(db, "order", 1, D(10), [(9, "AH Biologisch Courgette", 1)])  # te lang geleden: niet meer 'in huis'
    client = TestClient(app)
    assert client.get("/api/cook-with").json()["suggestions"] == []  # één treffer is te weinig
    _trip(db, "order", 2, D(0), [(9, "AH Biologisch Courgette", 1)])
    assert len(client.get("/api/cook-with").json()["suggestions"]) == 1
    db.add(PlanEntry(date=str(date.today() + timedelta(days=2)), kind="recipe", recipe_id=r.id))
    db.commit()
    assert client.get("/api/cook-with").json()["suggestions"] == []  # staat al op het menu


def test_pantry_products_are_not_inventory(db):  # noqa: F811
    flour = _ing("bloem", 1)
    flour["auto_skip"] = True  # basisvoorraad: Miso slaat het zelf over
    flour["skip"] = True
    _recipe(db, "Pannenkoek", [flour, _ing("melk", 2), _ing("ei", 3)])
    _trip(db, "order", 1, D(1), [(7, "AH Tarwebloem", 1), (8, "AH Eieren", 1)])
    out = TestClient(app).get("/api/cook-with").json()
    assert [b["name"] for b in out["inventory"]["bought"]] == ["AH Eieren"]
    assert out["suggestions"] == []


def test_empty_inventory(db):  # noqa: F811
    _recipe(db, "Pannenkoek", [_ing("melk", 2), _ing("ei", 3)])
    out = TestClient(app).get("/api/cook-with").json()
    assert out["suggestions"] == [] and out["inventory"] == {"freezer": [], "bought": []}


def test_weekmenu_page_has_cookwith_section(db):  # noqa: F811
    assert 'id="cookwith"' in TestClient(app).get("/weekmenu").text
