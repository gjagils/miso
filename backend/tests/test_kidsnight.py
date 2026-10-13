"""Kids-kookavond (D8): vlag "makkelijk met kinderen", vaste weekdag, voorrang in voorstellen."""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app import kidsnight, planning, wishes
from app.api import routes
from app.main import app
from app.models import Recipe
from app.nutrition import suggest_week
from tests.test_health import prof
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)
from tests.test_wishes import _profile


def test_fit_only_on_kids_day_for_flagged_recipes():
    kid, plain = Recipe(name="a", kid_friendly=True), Recipe(name="b", kid_friendly=False)
    wednesday = "2026-10-14"
    assert kidsnight.fit(kid, wednesday, 2, 8.0) == (8.0, "makkelijk met kinderen")
    assert kidsnight.fit(kid, wednesday, 3, 8.0) == (0.0, "")   # andere weekdag
    assert kidsnight.fit(plain, wednesday, 2, 8.0) == (0.0, "")  # zonder vlag
    assert kidsnight.fit(kid, wednesday, None, 8.0) == (0.0, "")  # geen kids-avond ingesteld
    assert not kidsnight.is_kids_day("onzin", 2)


def test_setting_roundtrip_via_api_and_form(db):  # noqa: F811
    client = TestClient(app)
    assert client.get("/api/plan/settings").json()["kids_weekday"] is None
    out = client.patch("/api/plan/settings", json={"kids_weekday": 2}).json()
    assert out["kids_weekday"] == 2 and planning.kids_weekday(db) == 2
    assert client.patch("/api/plan/settings", json={"kids_weekday": -1}).json()["kids_weekday"] is None
    assert client.patch("/api/plan/settings", json={"kids_weekday": 9}).status_code == 422
    client.post("/settings/plan", data={"household_size": 4, "order_weekday": 6, "week_budget": 0, "kids_weekday": 4})
    assert planning.kids_weekday(db) == 4
    assert 'name="kids_weekday"' in client.get("/settings").text


def test_flag_via_api_and_kid_cannot_set_it(db):  # noqa: F811
    r = _recipe(db, "Pannenkoeken", [])
    client = TestClient(app)
    out = client.patch(f"/api/recipes/{r.id}/flags", json={"kid_friendly": True}).json()
    assert out["ok"] and out["recipe"]["kid_friendly"] is True
    assert client.get("/api/recipes").json()["recipes"][0]["kid_friendly"] is True
    assert "Makkelijk met kinderen" in client.get(f"/recipe/{r.id}").text
    client.cookies.set("miso_member", "hannah")  # een kind
    denied = client.patch(f"/api/recipes/{r.id}/flags", json={"kid_friendly": False})
    assert denied.status_code == 403
    assert client.get("/api/recipes").json()["recipes"][0]["kid_friendly"] is True


def test_week_suggestion_prefers_kid_friendly_on_kids_day():
    cands = []
    for i in (10, 11):
        r = Recipe(name=f"r{i}", kid_friendly=(i == 11)); r.id = i
        cands.append((r, prof()))  # identieke profielen: alleen de vlag maakt het verschil
    wednesday, thursday = "2026-10-14", "2026-10-15"
    out = suggest_week([], cands, [wednesday], kids_weekday=2, today=date(2026, 10, 13))
    assert out[0]["recipe_id"] == 11 and "makkelijk met kinderen" in out[0]["redenen"]
    out = suggest_week([], cands, [thursday], kids_weekday=2, today=date(2026, 10, 13))
    assert "makkelijk met kinderen" not in out[0]["redenen"]


def test_propose_prefers_kid_friendly_on_kids_day(db):  # noqa: F811
    plain = _recipe(db, "Rijst met kip", [_ing("300 g rijst", 1), _ing("kip", 2)])
    _profile(db, plain, "rijst")
    easy = _recipe(db, "Rijst met worstjes", [_ing("300 g rijst", 1), _ing("worstjes", 3)])
    easy.kid_friendly = True
    db.commit()
    _profile(db, easy, "rijst")
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    wednesday = monday + timedelta(days=2)
    planning.set_setting(db, "kids_weekday", "2")
    options = wishes.propose(db, monday, {str(wednesday): "rijst"}, today=date.today())[0]["options"]
    assert options[0]["recipe_id"] == easy.id and options[0]["kids_night"] is True and options[0]["kid_friendly"] is True
    assert options[1]["kids_night"] is False
    planning.set_setting(db, "kids_weekday", "-1")
    options = wishes.propose(db, monday, {str(wednesday): "rijst"}, today=date.today())[0]["options"]
    assert all(o["kids_night"] is False for o in options)
