"""AH-maaltijdpakketten als recepten."""
import asyncio

from app import packs
from app.models import Recipe
from tests.test_routes import db  # noqa: F401  (fixture)

PACKS = [{"id": 1, "name": "AH Gesneden verspakket gehaktschotel", "unit_size": "2-3 pers|15 min", "available": True},
         {"id": 2, "name": "AH Groentesoep verspakket", "unit_size": "4 pers", "available": True},
         {"id": 3, "name": "AH Kip siam verspakket", "unit_size": "4 pers", "available": True}]


def test_best_pack_is_strict():
    assert packs.best_pack("1 AH verspakket groentesoep", PACKS)["id"] == 2
    assert packs.best_pack("1 AH verspakket paprikasoep", PACKS) is None
    assert packs.best_pack("1 AH verspakket kip Hawaï", PACKS) is None
    assert packs.best_pack("770 g AH gesneden verspakketten gehaktschotel", PACKS)["id"] == 1


def test_sync_adds_updates_and_archives(db, monkeypatch):
    recipes = [{"id": 10, "title": "AH verspakket groentesoep"}, {"id": 11, "title": "AH verspakket paprikasoep"}]

    async def fake_recipes():
        return recipes

    async def fake_packs():
        return PACKS

    async def fake_get(rid):
        return rid

    def fake_convert(rid):
        name = {10: "AH verspakket groentesoep", 11: "AH verspakket paprikasoep"}[rid]
        return {"name": name, "description": "", "servings": "4 personen", "total_time": "20 min",
                "ingredients": [{"text": f"1 {name}", "search": name, "skip": False, "quantity": 1, "product": None},
                                {"text": "1 ui", "search": "ui", "skip": False, "quantity": 1, "product": None}],
                "instructions": ["Kook."], "image_url": ""}

    monkeypatch.setattr(packs, "pack_recipes", fake_recipes)
    monkeypatch.setattr(packs, "current_packs", fake_packs)
    monkeypatch.setattr(packs.ah_client, "get_recipe", fake_get)
    monkeypatch.setattr(packs, "convert_ah_recipe", fake_convert)
    first = asyncio.run(packs.sync(db))
    assert first["new"] == 1 and first["error"] is None
    soup = db.query(Recipe).one()
    assert soup.collection == "maaltijdpakket" and soup.ingredients[0]["product"]["id"] == 2

    monkeypatch.setattr(packs, "current_packs", lambda: _none())  # groentesoep niet meer te koop
    second = asyncio.run(packs.sync(db))
    db.refresh(soup)
    assert second["archived"] == 1 and soup.archived


async def _none():
    return []
