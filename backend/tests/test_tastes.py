"""Smaak per persoon: voorkeuren, afkeer afleiden uit 👎, en gebruik in de voorstellen."""
from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from app import database, tastes, wishes
from app.api import family, routes
from app.main import app
from app.models import Rating
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)


@pytest.fixture()
def fam(db, monkeypatch):  # noqa: F811
    factory = sessionmaker(bind=db.get_bind())
    monkeypatch.setattr(database, "SessionLocal", factory)
    monkeypatch.setattr(family, "SessionLocal", factory)
    return db


def test_term_matching_rules():
    assert tastes.term_in_text("paprika", "2 puntpaprika's | kip")  # lange term: ook in een samenstelling
    assert tastes.term_in_text("ui", "1 ui, gesnipperd") and tastes.term_in_text("ui", "2 uien")
    assert not tastes.term_in_text("ui", "kruiden en fruit")  # korte term alleen aan het begin van een woord
    assert not tastes.term_in_text("", "alles")
    assert tastes.clean_term("  Rode   PAPRIKA ") == "rode paprika"


def test_preferences_crud_and_validation(fam):
    client = TestClient(app)
    assert client.post("/api/members/hannah/preferences", json={"term": " Paprika "}).json()["preference"]["term"] == "paprika"
    assert client.post("/api/members/hannah/preferences", json={"term": "kip", "kind": "like"}).json()["ok"]
    assert client.post("/api/members/hannah/preferences", json={"term": "x"}).status_code == 400
    assert client.post("/api/members/hannah/preferences", json={"term": "ui", "kind": "haat"}).status_code == 400
    assert client.post("/api/members/niemand/preferences", json={"term": "ui"}).status_code == 404
    # dezelfde term opnieuw zet alleen de soort om
    again = client.post("/api/members/hannah/preferences", json={"term": "paprika", "kind": "like"}).json()
    hannah = next(m for m in again["members"] if m["id"] == "hannah")
    assert sorted((p["term"], p["kind"]) for p in hannah["preferences"]) == [("kip", "like"), ("paprika", "like")]
    got = client.get("/api/preferences").json()
    assert got["ok"] and [m["name"] for m in got["members"]] == ["Gerd-Jan", "Nelleke", "Hannah", "Suze"]
    pid = next(p["id"] for p in hannah["preferences"] if p["term"] == "kip")
    assert client.delete(f"/api/members/suze/preferences/{pid}").status_code == 404  # niet van Suze
    assert client.delete(f"/api/members/hannah/preferences/{pid}").json()["ok"]
    assert client.delete("/api/members/hannah/preferences/9999").status_code == 404


def test_suggest_dislikes_from_thumbs_down(fam):
    client = TestClient(app)
    paprika = [_recipe(fam, f"Paprika gerecht {i}", [_ing("2 rode paprika's"), _ing("rijst")]) for i in range(3)]
    other = _recipe(fam, "Pasta", [_ing("pasta"), _ing("rijst")])
    day = str(date.today())
    for r in paprika[:2]:
        fam.add(Rating(recipe_id=r.id, member_id="hannah", day=day, rating="down"))
    fam.add(Rating(recipe_id=other.id, member_id="hannah", day=day, rating="up"))
    fam.add(Rating(recipe_id=paprika[2].id, member_id="suze", day=day, rating="down"))  # maar één 👎: te weinig
    fam.commit()
    got = client.get("/api/preferences").json()["suggestions"]
    assert [(s["member_id"], s["term"], s["down"], s["up"]) for s in got] == [("hannah", "paprika", 2, 0)]
    assert got[0]["name"] == "Hannah"  # 'rijst' zit ook in het 👍-recept, dus geen voorstel

    # Bevestigen = als afkeer noteren; daarna niet meer voorgesteld
    client.post("/api/members/hannah/preferences", json={"term": "paprika", "kind": "dislike"})
    assert client.get("/api/preferences").json()["suggestions"] == []


def test_dismissed_suggestion_stays_away_and_up_votes_cancel(fam):
    client = TestClient(app)
    rs = [_recipe(fam, f"Gerecht {i}", [_ing("koriander")]) for i in range(4)]
    day = str(date.today())
    for r in rs[:3]:
        fam.add(Rating(recipe_id=r.id, member_id="suze", day=day, rating="down"))
    fam.add(Rating(recipe_id=rs[3].id, member_id="suze", day=day, rating="up"))  # 3 down tegen 1 up: nog steeds voorstel
    fam.commit()
    assert [s["term"] for s in client.get("/api/preferences").json()["suggestions"]] == ["koriander"]
    out = client.post("/api/preferences/dismiss", json={"member_id": "suze", "term": "koriander"}).json()
    assert out["ok"] and out["suggestions"] == []
    # ook de helper zelf houdt rekening met wat al weggewuifd is
    assert tastes.suggest_dislikes(fam, [{"id": "suze", "name": "Suze"}]) == []


def test_net_vote_per_recipe_counts_once(fam):
    r1 = _recipe(fam, "A", [_ing("selderij")])
    r2 = _recipe(fam, "B", [_ing("selderij")])
    day = str(date.today())
    for _ in range(3):  # drie keer 👎 voor hetzelfde recept telt als één recept
        fam.add(Rating(recipe_id=r1.id, member_id="hannah", day=day, rating="down"))
    fam.add(Rating(recipe_id=r2.id, member_id="hannah", day=day, rating="up"))
    fam.add(Rating(recipe_id=r2.id, member_id="hannah", day=day, rating="down"))  # netto 0: telt niet mee
    fam.commit()
    assert tastes.suggest_dislikes(fam, [{"id": "hannah", "name": "Hannah"}]) == []  # maar 1 recept met netto 👎


def test_taste_lowers_proposal_and_warns(fam):
    from tests.test_wishes import _profile

    with_pepper = _recipe(fam, "Rijst met paprika", [_ing("300 g rijst", 1), _ing("2 paprika's", 2)])
    plain = _recipe(fam, "Rijst met kip", [_ing("300 g rijst", 1), _ing("kip", 3)])
    for r in (with_pepper, plain):
        _profile(fam, r, "rijst")
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    client = TestClient(app)
    base = wishes.propose(fam, monday, {str(monday): "rijst"}, today=date.today())[0]["options"]
    assert {o["recipe_id"] for o in base} == {with_pepper.id, plain.id}
    client.post("/api/members/hannah/preferences", json={"term": "paprika", "kind": "dislike"})
    out = wishes.propose(fam, monday, {str(monday): "rijst"}, today=date.today())[0]["options"]
    assert out[0]["recipe_id"] == plain.id and out[0]["avoid"] == []
    assert out[1]["recipe_id"] == with_pepper.id and out[1]["avoid"] == ["Hannah lust geen paprika"]
    client.post("/api/members/suze/preferences", json={"term": "kip", "kind": "like"})
    out = wishes.propose(fam, monday, {str(monday): "rijst"}, today=date.today())[0]["options"]
    assert out[0]["recipe_id"] == plain.id  # smaak voor kip maakt het alleen maar duidelijker


def test_taste_in_week_suggest_reasons(fam):
    from app.nutrition import save_profile
    from tests.test_health import prof

    a = _recipe(fam, "Met paprika", [_ing("paprika", 1)])
    b = _recipe(fam, "Met kip", [_ing("kip", 2)])
    for r in (a, b):
        save_profile(fam, r.id, prof())
    client = TestClient(app)
    client.post("/api/members/hannah/preferences", json={"term": "paprika", "kind": "dislike"})
    client.post("/api/members/suze/preferences", json={"term": "kip", "kind": "like"})
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    resp = client.post("/api/week/suggest", json={"week": str(monday)}).json()
    by = {v["recipe_id"]: v for v in resp["voorstel"]}
    assert "Hannah lust geen paprika" in by[a.id]["redenen"] and "Suze is dol op kip" in by[b.id]["redenen"]
    assert resp["voorstel"][0]["recipe_id"] == b.id


def test_kids_cannot_change_tastes(fam):
    client = TestClient(app, headers={"X-Miso-Member": "hannah"})
    assert client.post("/api/members/hannah/preferences", json={"term": "paprika"}).status_code == 403
    assert client.delete("/api/members/hannah/preferences/1").status_code == 403
    assert client.post("/api/preferences/dismiss", json={"member_id": "hannah", "term": "x"}).status_code == 403
    assert client.get("/api/preferences").status_code == 200  # meekijken mag
