"""Stemmen op kandidaten (D7): ronde starten, stemmen (max 3), sluiten en lege dagen vullen."""
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from app import database, voting
from app.api import family, routes
from app.main import app
from app.models import PlanEntry
from tests.test_routes import _recipe, db  # noqa: F401  (fixture)


@pytest.fixture()
def fam(db, monkeypatch):  # noqa: F811
    factory = sessionmaker(bind=db.get_bind())
    monkeypatch.setattr(database, "SessionLocal", factory)
    monkeypatch.setattr(family, "SessionLocal", factory)
    return db


def _week():
    return str(routes.monday_of(date.today()) + timedelta(days=7))


def _recipes(db, n=5):  # noqa: F811
    return [_recipe(db, f"Gerecht {i}", []) for i in range(n)]


def test_start_default_candidates_and_empty_poll(fam):
    client = TestClient(app)
    assert client.get(f"/api/vote-poll?week={_week()}").json()["open"] is False
    assert client.post("/api/vote-poll", json={"week": _week()}).json()["ok"] is False  # geen recepten
    _recipes(fam, 7)
    out = client.post("/api/vote-poll", json={"week": _week()}).json()
    assert out["ok"] and out["open"] and len(out["candidates"]) == voting.DEFAULT_CANDIDATES
    assert out["max_votes"] == 3 and out["my_votes"] == 0


def test_voting_rules(fam):
    rs = _recipes(fam, 5)
    client = TestClient(app)
    client.post("/api/vote-poll", json={"week": _week(), "recipe_ids": [r.id for r in rs]})
    anonymous = client.post("/api/votes", json={"week": _week(), "recipe_id": rs[0].id}).json()
    assert not anonymous["ok"] and "wie je bent" in anonymous["error"]
    client.cookies.set("miso_member", "hannah")  # een kind mag stemmen
    for r in rs[:3]:
        assert client.post("/api/votes", json={"week": _week(), "recipe_id": r.id}).json()["ok"]
    fourth = client.post("/api/votes", json={"week": _week(), "recipe_id": rs[3].id}).json()
    assert not fourth["ok"] and "3 stemmen" in fourth["error"]
    out = client.post("/api/votes", json={"week": _week(), "recipe_id": rs[0].id, "on": False}).json()
    assert out["ok"] and out["my_votes"] == 2
    assert client.post("/api/votes", json={"week": _week(), "recipe_id": rs[3].id}).json()["ok"]
    # dubbel stemmen telt één keer; onbekend recept mag niet
    client.post("/api/votes", json={"week": _week(), "recipe_id": rs[3].id})
    state = client.get(f"/api/vote-poll?week={_week()}").json()
    assert next(c for c in state["candidates"] if c["recipe_id"] == rs[3].id)["votes"] == 1
    assert state["voted_count"] == 1 and all(c["voters"] in ([], ["H"]) for c in state["candidates"])
    stray = _recipe(fam, "Buiten de ronde", [])
    assert not client.post("/api/votes", json={"week": _week(), "recipe_id": stray.id}).json()["ok"]


def test_close_fills_empty_days_by_votes(fam):
    rs = _recipes(fam, 4)
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    taken = PlanEntry(date=str(monday), kind="stock", recipe_id=0, text="Pizza")  # maandag is al bezet
    fam.add(taken)
    fam.commit()
    client = TestClient(app)
    client.post("/api/vote-poll", json={"week": str(monday), "recipe_ids": [r.id for r in rs]})
    for member, picks in {"gerd-jan": [0, 1], "nelleke": [0, 2], "hannah": [0]}.items():
        client.cookies.set("miso_member", member)
        for i in picks:
            client.post("/api/votes", json={"week": str(monday), "recipe_id": rs[i].id})
    client.cookies.clear()
    out = client.post("/api/vote-poll/close", json={"week": str(monday)}).json()
    assert out["ok"] and out["placed"] == 3 and out["no_votes"] == 1 and out["no_room"] == 0
    by_day = {e["date"]: e["title"] for e in out["entries"]}
    assert by_day[str(monday)] == "Pizza"  # bezette dag blijft
    assert by_day[str(monday + timedelta(days=1))] == "Gerecht 0"  # 3 stemmen: eerst
    assert set(by_day.values()) == {"Pizza", "Gerecht 0", "Gerecht 1", "Gerecht 2"}
    assert "Gerecht 3" not in by_day.values()  # geen stem, geen plek
    assert client.get(f"/api/vote-poll?week={monday}").json()["open"] is False
    assert fam.query(PlanEntry).filter(PlanEntry.kind == "recipe").count() == 3


def test_close_without_free_days_and_unknown_poll(fam):
    rs = _recipes(fam, 3)
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    for i in range(7):
        fam.add(PlanEntry(date=str(monday + timedelta(days=i)), kind="stock", recipe_id=0, text="x"))
    fam.commit()
    client = TestClient(app)
    assert client.post("/api/vote-poll/close", json={"week": str(monday)}).status_code == 404
    client.post("/api/vote-poll", json={"week": str(monday), "recipe_ids": [r.id for r in rs]})
    client.cookies.set("miso_member", "gerd-jan")
    client.post("/api/votes", json={"week": str(monday), "recipe_id": rs[0].id})
    client.cookies.clear()
    out = client.post("/api/vote-poll/close", json={"week": str(monday)}).json()
    assert out["placed"] == 0 and out["no_room"] == 1


def test_kids_vote_but_cannot_start_close_or_cancel(fam):
    rs = _recipes(fam, 3)
    client = TestClient(app)
    client.post("/api/vote-poll", json={"week": _week(), "recipe_ids": [r.id for r in rs]})
    client.cookies.set("miso_member", "suze")
    assert client.post("/api/votes", json={"week": _week(), "recipe_id": rs[0].id}).json()["ok"]
    assert client.post("/api/vote-poll", json={"week": _week()}).status_code == 403
    assert client.post("/api/vote-poll/close", json={"week": _week()}).status_code == 403
    assert client.delete(f"/api/vote-poll?week={_week()}").status_code == 403
    assert client.get(f"/api/vote-poll?week={_week()}").json()["candidates"][0]["mine"] in (True, False)
    client.cookies.set("miso_member", "gerd-jan")
    assert client.delete(f"/api/vote-poll?week={_week()}").json()["ok"]
    assert client.delete(f"/api/vote-poll?week={_week()}").status_code == 404


def test_weekmenu_page_vote_section_and_kid_view(fam):
    client = TestClient(app)
    page = client.get("/weekmenu").text
    assert 'id="vote"' in page and 'id="vt-list"' in page
    assert 'id="tpl-add"' in page and "const IS_KID = false" in page
    client.cookies.set("miso_member", "hannah")
    kid_page = client.get("/weekmenu").text
    assert "const IS_KID = true" in kid_page and 'id="tpl-add"' not in kid_page  # sjablonen zijn voor ouders


def test_leftover_day_counts_as_taken(fam):
    rs = _recipes(fam, 3)
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    fam.add(PlanEntry(date=str(monday), kind="leftover", recipe_id=rs[2].id, text=""))
    fam.commit()
    client = TestClient(app)
    client.post("/api/vote-poll", json={"week": str(monday), "recipe_ids": [rs[0].id, rs[1].id]})
    client.cookies.set("miso_member", "gerd-jan")
    client.post("/api/votes", json={"week": str(monday), "recipe_id": rs[0].id})
    client.cookies.clear()
    out = client.post("/api/vote-poll/close", json={"week": str(monday)}).json()
    day = next(e["date"] for e in out["entries"] if e["kind"] == "recipe")
    assert day == str(monday + timedelta(days=1))  # niet op de dag van het restje
