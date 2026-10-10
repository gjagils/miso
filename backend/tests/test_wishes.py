"""Plannen met wensen per dag."""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app import wishes
from app.api import routes
from app.main import app
from app.models import PlanEntry, RecipeProfile
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)


def _profile(db, recipe, basis, eiwit="kip", keuken="overig"):
    import json

    from app.nutrition import PROFILE_VERSION

    p = {"kcal": 600, "groente_g": 200, "eiwit": eiwit, "basis": basis, "keuken": keuken, "volkoren": False,
         "schijf": {}, "score": 4, "toelichting": ""}
    db.add(RecipeProfile(recipe_id=recipe.id, profile_json=json.dumps(p), version=PROFILE_VERSION))
    db.commit()


def test_normalize():
    assert wishes.normalize("iets met rijst") == "rijst"
    assert wishes.normalize("Wraps") == "wraps"
    assert wishes.normalize("geen idee") == "vrij"
    assert wishes.normalize("uit de vriezer") == "vriezer"
    assert wishes.normalize("lasagne") == "lasagne"


def test_propose_and_apply(db):
    nasi = _recipe(db, "Nasi goreng", [_ing("300 g rijst", 1)])
    _profile(db, nasi, "rijst")
    taco = _recipe(db, "Taco's met kip", [_ing("8 tortilla's", 2)])
    _profile(db, taco, "wraps", keuken="mexicaans")
    lasagne = _recipe(db, "Lasagne bolognese", [_ing("lasagnebladen", 3)])
    _profile(db, lasagne, "pasta", eiwit="vlees")
    soup = _recipe(db, "Groentecurry", [_ing("tomaten", 4)])
    _profile(db, soup, "geen", eiwit="vega")
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    d = [str(monday + timedelta(days=i)) for i in range(5)]
    client = TestClient(app)

    async def fake_search(text, size=12):
        return [{"id": 900 + len(text), "title": f"AH {text}", "image_url": "", "time": "25 min"}]

    import pytest  # noqa: F401
    routes.ah_client.search_recipes, real = fake_search, routes.ah_client.search_recipes
    res = client.post("/api/plan/propose", json={"week": str(monday), "wishes": {
        d[0]: "rijst", d[1]: "iets met wraps", d[2]: "vriezer", d[3]: "lasagne", d[4]: "geen idee"}}).json()
    routes.ah_client.search_recipes = real
    by = {x["date"]: x for x in res["days"]}
    assert by[d[0]]["options"][-1]["allerhande"] and len(by[d[0]]["options"]) == 2  # 1 eigen + aanvulling
    assert by[d[0]]["options"][0]["name"] == "Nasi goreng"
    assert by[d[1]]["options"][0]["name"] == "Taco's met kip"
    assert by[d[2]]["kind"] == "vriezer"
    assert by[d[3]]["options"][0]["name"] == "Lasagne bolognese"
    assert by[d[4]]["options"][0]["name"] == "Groentecurry"  # de andere drie zijn al gekozen
    tomato = _recipe(db, "Tomatensoep", [])
    vrij = client.post("/api/plan/propose", json={"week": str(monday), "wishes": {d[4]: "geen idee"}}).json()
    assert tomato.name not in [o["name"] for o in vrij["days"][0]["options"]]  # geen soep bij "geen idee"

    choices = [{"date": d[0], "kind": "recipe", "recipe_id": nasi.id}, {"date": d[2], "kind": "vriezer"},
               {"date": d[4], "kind": "recipe", "recipe_id": soup.id}]
    out = client.post("/api/plan/apply", json={"week": str(monday), "choices": choices, "swapped": [lasagne.id]}).json()
    assert out["ok"] and out["added"] == 3
    kinds = sorted(e.kind for e in db.query(PlanEntry).all())
    assert kinds == ["recipe", "recipe", "stock"]
    db.refresh(lasagne)
    assert lasagne.swapped_count == 1
    again = client.post("/api/plan/apply", json={"week": str(monday), "choices": choices}).json()
    assert again["added"] == 0  # bezette dagen blijven staan
    page = client.get(f"/plannen?week={monday}").text
    assert "Waar hebben jullie zin in?" in page and "Weekend ook plannen" in page and "Nasi goreng" in page


def test_change_day_replaces_only_on_apply(db):
    a = _recipe(db, "Nasi goreng", [])
    b = _recipe(db, "Pasta pesto", [])
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    day = str(monday)
    client = TestClient(app)
    client.post("/api/plan/apply", json={"week": str(monday), "choices": [{"date": day, "kind": "recipe", "recipe_id": a.id}]})
    res = client.post("/api/plan/propose", json={"week": str(monday), "wishes": {day: "pasta"}, "replace": [day]}).json()
    assert res["days"][0]["kind"] == "recipe"  # dag telt als open bij Wijzig
    assert db.query(PlanEntry).count() == 1  # nog niets weggehaald
    client.post("/api/plan/apply", json={"week": str(monday), "choices": [
        {"date": day, "kind": "recipe", "recipe_id": b.id, "replace": True}]})
    assert [e.recipe_id for e in db.query(PlanEntry).all()] == [b.id]
