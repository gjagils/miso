"""Weeksjablonen (F9): week opslaan, terugzetten op een andere week, bezette dagen en verwijderde recepten."""
from datetime import timedelta

from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from app import database, planning
from app.api import family
from app.main import app
from app.models import PlanEntry
from tests.test_plan import _future_monday, _g, _recipe4
from tests.test_routes import db  # noqa: F401  (fixture)


def _fill(client, monday, r1, r2):
    client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r1.id, "cook_double": "tomorrow", "persons": 3})
    client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=2)), "recipe_id": r2.id})
    client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=4)), "kind": "stock", "text": "Pizza halen",
                                           "extras": [{"text": "pizza"}]})


def test_save_and_apply_template_on_other_week(db):
    r1 = _recipe4(db, "Lasagne", [_g("500 g gehakt", 2, 500, 500)])
    r2 = _recipe4(db, "Pasta", [_g("500 g pasta", 1, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    _fill(client, monday, r1, r2)
    saved = client.post("/api/plan/templates", json={"name": "Standaardweek", "week": str(monday)}).json()
    assert saved["ok"] and saved["template"]["count"] == 3
    assert [d["label"] for d in saved["template"]["days"]] == ["Lasagne", "Pasta", "Pizza halen"]
    listed = client.get("/api/plan/templates").json()["templates"]
    assert [t["name"] for t in listed] == ["Standaardweek"]

    target = monday + timedelta(days=7)
    out = client.post(f"/api/plan/templates/{saved['template']['id']}/apply", json={"week": str(target)}).json()
    assert out["ok"] and out["placed"] == 3 and out["skipped_busy"] == 0
    entries = planning.week_entries(db, target)
    kinds = sorted((e.date, e.kind) for e in entries)
    assert kinds == [(str(target), "recipe"), (str(target + timedelta(days=1)), "leftover"),
                     (str(target + timedelta(days=2)), "recipe"), (str(target + timedelta(days=4)), "stock")]
    first = next(e for e in entries if e.kind == "recipe" and e.date == str(target))
    assert first.persons == 3 and first.cook_double == "tomorrow"
    rest = next(e for e in entries if e.kind == "leftover")
    assert rest.source_entry_id == first.id
    stock = next(e for e in entries if e.kind == "stock")
    assert stock.text == "Pizza halen" and stock.extras[0]["text"] == "pizza"


def test_apply_keeps_busy_days_unless_replace(db):
    r1 = _recipe4(db, "Lasagne", [_g("500 g gehakt", 2, 500, 500)])
    r2 = _recipe4(db, "Pasta", [_g("500 g pasta", 1, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    _fill(client, monday, r1, r2)
    tid = client.post("/api/plan/templates", json={"name": "A", "week": str(monday)}).json()["template"]["id"]
    # de dag zelf is al bezet: standaard blijft staan wat er stond
    again = client.post(f"/api/plan/templates/{tid}/apply", json={"week": str(monday)}).json()
    assert again["placed"] == 0 and again["skipped_busy"] == 3
    assert len([e for e in planning.week_entries(db, monday) if e.kind == "recipe"]) == 2
    replaced = client.post(f"/api/plan/templates/{tid}/apply", json={"week": str(monday), "replace": True}).json()
    assert replaced["placed"] == 3
    assert len([e for e in planning.week_entries(db, monday) if e.kind == "recipe"]) == 2  # niet verdubbeld


def test_deleted_recipe_is_skipped_and_empty_week_not_saved(db):
    r1 = _recipe4(db, "Lasagne", [_g("500 g gehakt", 2, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    empty = client.post("/api/plan/templates", json={"name": "Leeg", "week": str(monday)}).json()
    assert not empty["ok"] and "leeg" in empty["error"]
    client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r1.id})
    tid = client.post("/api/plan/templates", json={"name": "Eén", "week": str(monday)}).json()["template"]["id"]
    for e in planning.week_entries(db, monday):
        db.delete(e)
    db.delete(r1)
    db.commit()
    out = client.post(f"/api/plan/templates/{tid}/apply", json={"week": str(monday)}).json()
    assert out["placed"] == 0 and out["skipped_gone"] == 1
    assert client.get("/api/plan/templates").json()["templates"][0]["days"][0]["missing"] is True


def test_save_same_name_overwrites_and_delete(db):
    r1 = _recipe4(db, "Lasagne", [_g("500 g gehakt", 2, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    client.post("/api/plan/entries", json={"date": str(monday), "recipe_id": r1.id})
    client.post("/api/plan/templates", json={"name": "Week", "week": str(monday)})
    client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=1)), "recipe_id": r1.id})
    again = client.post("/api/plan/templates", json={"name": "Week", "week": str(monday)}).json()
    assert again["template"]["count"] == 2
    listed = client.get("/api/plan/templates").json()["templates"]
    assert len(listed) == 1
    assert client.delete(f"/api/plan/templates/{listed[0]['id']}").json()["ok"]
    assert client.get("/api/plan/templates").json()["templates"] == []
    assert client.delete("/api/plan/templates/999").status_code == 404


def test_kids_cannot_save_apply_or_delete_templates(db, monkeypatch):
    factory = sessionmaker(bind=db.get_bind())
    monkeypatch.setattr(database, "SessionLocal", factory)
    monkeypatch.setattr(family, "SessionLocal", factory)
    client = TestClient(app)
    client.cookies.set("miso_member", "hannah")
    assert client.post("/api/plan/templates", json={"name": "X"}).status_code == 403
    assert client.delete("/api/plan/templates/1").status_code == 403
    assert client.get("/api/plan/templates").status_code == 200  # kijken mag


def test_weekmenu_page_has_template_section(db):
    html = TestClient(app).get("/weekmenu").text
    assert "Week als sjabloon" in html and 'id="tpl-add"' in html


def test_leftover_day_is_never_overwritten(db):  # noqa: F811
    r1 = _recipe4(db, "Lasagne", [_g("500 g gehakt", 2, 500, 500)])
    r2 = _recipe4(db, "Pasta", [_g("500 g pasta", 1, 500, 500)])
    monday = _future_monday()
    client = TestClient(app)
    client.post("/api/plan/entries", json={"date": str(monday + timedelta(days=1)), "recipe_id": r2.id})
    tid = client.post("/api/plan/templates", json={"name": "A", "week": str(monday)}).json()["template"]["id"]
    target = monday + timedelta(days=7)
    # in de doelweek staat maandag een kookdag met restje op dinsdag
    client.post("/api/plan/entries", json={"date": str(target), "recipe_id": r1.id, "cook_double": "tomorrow"})
    for replace in (False, True):
        out = client.post(f"/api/plan/templates/{tid}/apply", json={"week": str(target), "replace": replace}).json()
        assert out["placed"] == 0 and out["skipped_busy"] == 1  # dinsdag heeft een restje
        kinds = sorted((e.date, e.kind) for e in planning.week_entries(db, target))
        assert kinds == [(str(target), "recipe"), (str(target + timedelta(days=1)), "leftover")]
