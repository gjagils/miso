from app.nutrition import _clean, analyze_week, suggest_week
from app.models import Recipe
from tests.test_routes import db  # noqa: F401  (fixture)


def prof(eiwit="vlees", basis="pasta", keuken="italiaans", kcal=600, veg=180, score=4):
    return _clean({"kcal": kcal, "groente_g": veg, "eiwit": eiwit, "basis": basis, "keuken": keuken, "score": score,
                   "schijf": {"groente_fruit": True, "zetmeel": True, "eiwit": True}})


def test_clean_bounds_and_defaults():
    p = _clean({"kcal": "9999", "groente_g": -5, "eiwit": "draak", "basis": "PASTA", "score": 9})
    assert p["kcal"] == 2000 and p["groente_g"] == 0 and p["eiwit"] == "vlees" and p["basis"] == "pasta" and p["score"] == 5


def test_week_signals_repetition_fish_veg():
    week = [(f"2026-10-0{i}", prof(basis="pasta", veg=100)) for i in range(5, 9)]
    texts = " ".join(s["tekst"] for s in analyze_week(week)["signalen"])
    assert "4x pasta" in texts and "vis" in texts and "groente" in texts


def test_suggest_prefers_variety_and_fish():
    planned = [{"recipe_id": 1, "profiel": prof(basis="pasta")}, {"recipe_id": 2, "profiel": prof(basis="pasta")}]
    cands = []
    for i, p in enumerate([prof(basis="pasta"), prof(eiwit="vis", basis="rijst", keuken="aziatisch"),
                           prof(eiwit="vega", basis="aardappel", keuken="hollands")], start=10):
        r = Recipe(name=f"r{i}"); r.id = i
        cands.append((r, p))
    out = suggest_week(planned, cands, ["2026-10-09", "2026-10-10"])
    assert [c["recipe_id"] for c in out] == [11, 12]  # vis/rijst en vega/aardappel, niet nog eens pasta


def test_suggest_uses_context_with_reasons():
    from datetime import date, timedelta

    cands = []
    for i in range(10, 13):
        r = Recipe(name=f"r{i}"); r.id = i
        cands.append((r, prof()))  # drie identieke profielen: alleen de context maakt het verschil
    today = date(2026, 10, 13)
    ctx = {10: {"last_cooked": str(today - timedelta(days=7))},
           11: {"fans": ["Hannah"], "last_cooked": str(today - timedelta(days=28)),
                "bonus_saving": 2.8, "bonus_count": 2, "cost_pp": 3.2},
           12: {"thumbs_up": 0, "thumbs_down": 2, "last_cooked": str(today - timedelta(days=60))}}
    out = suggest_week([], cands, ["2026-10-14", "2026-10-15", "2026-10-16"], prefs={12: -50}, context=ctx, today=today)
    assert [c["recipe_id"] for c in out] == [11, 10, 12]
    assert out[0]["redenen"] == ["favoriet van Hannah", "in de bonus (−€2,80)", "4 weken niet gegeten", "ongeveer €3,20 p.p."]
    assert out[2]["redenen"] == ["vaker 👎 dan 👍", "8 weken niet gegeten"]
    assert out[1]["uitleg"] == ""  # vorige week gegeten, niets bijzonders
    # Nooit gekookt krijgt een duwtje; wensen tellen zwaar
    out = suggest_week([], cands, ["2026-10-14"], context={10: {"wishes": ["Hannah", "Suze"]}}, today=today)
    assert out[0]["recipe_id"] == 10 and out[0]["redenen"] == ["nog nooit gekookt", "wens van Hannah, Suze"]


def test_week_suggest_endpoint_builds_context(db):  # noqa: F811
    from datetime import date, timedelta

    from fastapi.testclient import TestClient

    from app import ah_sync
    from app.api import routes
    from app.main import app
    from app.models import PlanEntry, Wish
    from app.nutrition import save_profile
    from tests.test_routes import _ing, _recipe

    a = _recipe(db, "Favoriet", [_ing("kip", 1)])
    b = _recipe(db, "Afknapper", [_ing("vis", 2)])
    for r in (a, b):
        save_profile(db, r.id, prof())
    b.thumbs_down, b.thumbs_up = 3, 0
    monday = routes.monday_of(date.today()) + timedelta(days=7)
    db.add(PlanEntry(date=str(date.today() - timedelta(days=40)), recipe_id=b.id, kind="recipe"))
    db.add(Wish(member_id="hannah", recipe_id=a.id, created_on=str(date.today())))
    db.commit()
    ah_sync.record_bonus(db, {"start": str(monday), "end": str(monday + timedelta(days=6)), "personal": 0, "groups": 0,
                              "products": {1: {"id": 1, "title": "Kip", "now": 3.0, "was": 4.0, "saving": 1.0, "mechanism": "25%"}}},
                         False)
    resp = TestClient(app).post("/api/week/suggest", json={"week": str(monday)}).json()
    assert resp["ok"] and [c["recipe_id"] for c in resp["voorstel"][:2]] == [a.id, b.id]
    assert resp["voorstel"][0]["redenen"] == ["in de bonus (−€1,00)", "nog nooit gekookt", "wens van Hannah"]
    assert "vaker 👎 dan 👍" in resp["voorstel"][1]["redenen"] and "5 weken niet gegeten" in resp["voorstel"][1]["redenen"]
