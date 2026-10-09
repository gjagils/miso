from app.nutrition import _clean, analyze_week, suggest_week
from app.models import Recipe


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
