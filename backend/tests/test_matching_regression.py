"""Regressietests voor het koppelen van ingrediënten aan AH-producten.

Offline: echte ingrediëntregels uit de recepten (tests/data/ingredient_lines.txt) en opgenomen
AH-zoekresultaten (tests/data/ah_search_fixture.json). Online (optioneel): `LIVE_AH=1 pytest -m live`.
"""
import asyncio
import json
import os
import re
from pathlib import Path

import pytest

from app.api import routes
from app.clients.mealie import clean_search
from app.matching import MATCH_VERSION, choose, is_equipment, is_pantry, needed, pack_size

DATA = Path(__file__).parent / "data"
LINES = [l.strip() for l in (DATA / "ingredient_lines.txt").read_text().splitlines() if l.strip()]
FIXTURE = json.loads((DATA / "ah_search_fixture.json").read_text())

UNIT_WORDS = {"g", "gr", "gram", "kg", "ml", "l", "cl", "dl", "el", "tl", "stuk", "stuks", "blik", "zakje", "bosje", "teen"}


@pytest.mark.parametrize("line,expected", [
    ("1 blik biologische zwarte bonen", "biologische zwarte bonen"),
    ("1kg kruimige aardappels", "kruimige aardappels"),
    ("1½ stuk(s) aubergine", "aubergine"),
    ("2 blokjes harde kaas", "harde kaas"),
    ("1 kuipje rode pesto met olijven", "rode pesto met olijven"),
    ("10g verse koriander", "verse koriander"),
    ("1 teen knoflook (geperst)", "knoflook"),
    ("1 courgette (zwart)", "courgette"),
    ("Ui (1 st) *", "Ui"),
    ("Roomboter 1½ el", "Roomboter"),
    ("Rode ui 1 stuks", "Rode ui"),
    ("Halloumi 75 g", "Halloumi"),
    ("250 g halloumi (in dikke plakken)", "halloumi"),
    ("½ bosje munt (blad geplukt)", "munt"),
    ("Duitse biefstuk* (1, 2, 3, 3, 4, 4)", "Duitse biefstuk"),
])
def test_search_terms_golden(line, expected):
    assert clean_search(line) == expected


def test_search_terms_hold_for_every_real_ingredient_line():
    bad = []
    for line in LINES:
        term = clean_search(line)
        first = term.split()[0].lower() if term.split() else ""
        if (re.match(r"^[\d½¼¾⅓⅔]+(?![\d-]*[a-z])", term) or any(c in term for c in "(,*")
                or (re.match(r"^[\d½¼¾⅓⅔]", line) and first in UNIT_WORDS)):
            bad.append((line, term))
    assert not bad, f"{len(bad)} ingrediënten met een slechte zoekterm, bv. {bad[:8]}"


@pytest.mark.parametrize("line,amount,unit", [
    ("250 g halloumi", 250, "g"), ("1kg kruimige aardappels", 1000, "g"), ("7 1/2 el olijfolie", 112.5, "ml"),
    ("1 1/2 el balsamico", 22.5, "ml"), ("½ bosje munt", 0.5, "bos"), ("1½ stuk(s) aubergine", 1.5, "stuk"),
    ("2 teentjes knoflook", 2, "stuk"), ("400 g tomaten in blik", 400, "g"), ("Roomboter 1½ el", 22.5, "ml"),
])
def test_amounts_golden(line, amount, unit):
    n = needed(line)
    assert n and n["amount"] == pytest.approx(amount) and n["unit"] == unit


@pytest.mark.parametrize("line", ["1", "1 stuk", "2 teentjes", "200 ml", "*in de koelkast bewaren"])
def test_lines_without_a_product_give_no_search_term(line):
    assert clean_search(line) == "" or line.startswith("*")


def test_amounts_are_sane_for_every_real_line():
    for line in LINES:
        n = needed(line)
        assert n is None or n["amount"] > 0, line


@pytest.mark.parametrize("line", ["zout", "peper en zout", "naar smaak peper en zout", "olijfolie", "water"])
def test_pantry(line):
    assert is_pantry(clean_search(line))


@pytest.mark.parametrize("line", ["keukenrasp", "grote koekenpan met deksel", "2 bakplaten met bakpapier"])
def test_equipment(line):
    assert is_equipment(clean_search(line))


@pytest.mark.parametrize("line", ["200 g halloumi", "1 courgette", "pannenkoekenmix 200 g", "panko 100 g"])
def test_real_food_is_not_equipment_or_pantry(line):
    assert not is_equipment(clean_search(line)) and not is_pantry(clean_search(line))


@pytest.mark.parametrize("query,must_contain,must_not", [
    ("halloumi", "halloumi", ()),
    ("munt", "munt", ("ricola",)),
    ("citroen", "citroen", ("bakmix", "cake", "radler")),
    ("rode ui", "rode ui", ()),
    ("quinoa", "quinoa", ()),
    ("knoflook", "knoflook", ("woksmaakmaker", "olijfmix")),
    ("tomatenpuree", "tomatenpuree", ()),
    ("koriander", "koriander", ("naanbrood",)),
    ("gember", "gember", ("siroop", "woksmaakmaker")),
])
def test_choose_on_recorded_ah_results(query, must_contain, must_not):
    product = choose(FIXTURE[query], query)
    assert product, f"geen product gekozen voor {query}"
    name = product["name"].lower()
    assert must_contain in name and not any(w in name for w in must_not), product["name"]


def test_choose_prefers_organic_when_available():
    assert "biologisch" in choose(FIXTURE["quinoa"], "quinoa")["name"].lower()


def _fake_search(monkeypatch):
    calls = []

    async def fake(query, size=10):
        calls.append(query)
        return [dict(p) for p in FIXTURE.get(query.lower(), [])]

    monkeypatch.setattr(routes.ah_client, "search_products", fake)
    return calls


def _ings(*texts):
    return [{"text": t, "search": t, "skip": False, "quantity": 1, "product": None} for t in texts]


def test_automatch_end_to_end_offline(monkeypatch):
    _fake_search(monkeypatch)
    ings = _ings("250 g halloumi (in dikke plakken)", "1 rode ui (in ringen)", "½ bosje munt", "zout",
                 "grote koekenpan met deksel", "2 el olijfolie", "1 teen knoflook")
    asyncio.run(routes._automatch(ings))
    by = {i["text"]: i for i in ings}
    assert by["250 g halloumi (in dikke plakken)"]["product"]["name"] == "AH Halloumi"
    assert by["250 g halloumi (in dikke plakken)"]["quantity"] == 2  # 250 g bij pakken van 225 g
    assert "rode uien" in by["1 rode ui (in ringen)"]["product"]["name"].lower()
    assert "munt" in by["½ bosje munt"]["product"]["name"].lower()
    for pantry in ("zout", "grote koekenpan met deksel", "2 el olijfolie"):
        assert by[pantry]["skip"] and by[pantry]["auto_skip"] and not by[pantry]["product"]
    assert all(i["match_v"] == MATCH_VERSION for i in ings)


def test_automatch_is_idempotent_and_keeps_manual_choices(monkeypatch):
    calls = _fake_search(monkeypatch)
    ings = _ings("200 g halloumi", "1 rode ui")
    ings[1]["product"] = {"id": 999, "name": "Mijn eigen keuze", "unit_size": "1 kg"}
    ings[1]["manual"] = True
    asyncio.run(routes._automatch(ings))
    first = json.dumps(ings, sort_keys=True)
    n_calls = len(calls)
    asyncio.run(routes._automatch(ings))
    assert json.dumps(ings, sort_keys=True) == first and len(calls) == n_calls  # geen nieuwe zoekopdrachten
    assert ings[1]["product"]["name"] == "Mijn eigen keuze"


def test_old_unversioned_matches_are_redone_but_manual_are_not(monkeypatch):
    _fake_search(monkeypatch)
    ings = _ings("200 g halloumi", "1 rode ui")
    ings[0]["product"] = {"id": 1, "name": "Ricola Citroen munt", "unit_size": "1 st"}  # oude, foute koppeling
    ings[1]["product"] = {"id": 2, "name": "Eigen product", "unit_size": "1 st"}
    ings[1]["manual"] = True
    asyncio.run(routes._automatch(ings))
    assert ings[0]["product"]["name"] == "AH Halloumi" and ings[1]["product"]["name"] == "Eigen product"


def test_automatch_survives_ah_outage(monkeypatch):
    async def boom(query, size=10):
        raise RuntimeError("AH down")

    monkeypatch.setattr(routes.ah_client, "search_products", boom)
    ings = _ings("200 g halloumi")
    assert asyncio.run(routes._automatch(ings)) == 0 and ings[0]["product"] is None


@pytest.mark.live
@pytest.mark.skipif(os.environ.get("LIVE_AH") != "1", reason="alleen met LIVE_AH=1 (gebruikt het echte AH)")
@pytest.mark.parametrize("query,word", [("halloumi", "halloumi"), ("rode ui", "ui"), ("quinoa", "quinoa"),
                                        ("kipfilet", "kip"), ("tomatenpuree", "tomatenpuree"), ("citroen", "citroen")])
def test_live_ah_search_returns_plausible_product(query, word):
    products = asyncio.run(routes.ah_client.search_products(query, size=12))
    product = choose(products, query)
    assert product and word in product["name"].lower() and product["id"]
    assert pack_size(product["unit_size"]) is not None or product["unit_size"]


def test_shopping_list_items_have_description_and_no_duplicate_products():
    from app.clients.ah import build_list_items

    body = build_list_items([
        {"product_id": 7, "quantity": 2, "name": "AH Halloumi"},
        {"product_id": 7, "quantity": 1, "name": "AH Halloumi"},
        {"product_id": 9, "name": "AH Rode uien"},
    ])
    assert [b["productId"] for b in body] == [7, 9]
    assert body[0]["quantity"] == 3 and body[0]["description"] == "AH Halloumi"
    assert all(b["type"] == "SHOPPABLE" and b["originCode"] == "PRD" and b["strikeThrough"] is False for b in body)


def test_learned_preference_is_used_instead_of_search(monkeypatch):
    calls = _fake_search(monkeypatch)
    ings = _ings("200 g halloumi")
    prefs = {"halloumi": {"id": 42, "name": "Mijn favoriete halloumi", "unit_size": "200 g"}}
    asyncio.run(routes._automatch(ings, prefs=prefs))
    assert ings[0]["product"]["name"] == "Mijn favoriete halloumi" and ings[0]["source"] == "geleerd"
    assert calls == []  # geen AH-zoekopdracht nodig


def test_basket_and_link_builders_never_order():
    from app.clients import ah

    assert ah.build_order_items([{"product_id": 1, "quantity": 2}, {"product_id": 1, "quantity": 0}]) == [
        {"productId": 1, "quantity": 2, "originCode": "PRD", "description": "", "strikethrough": False}]
    assert ah.build_add_multiple_url([{"product_id": 5, "quantity": 2.4}, {"product_id": 6}]) == \
        "https://www.ah.nl/mijnlijst/add-multiple?p=5%3A2&p=6%3A1"
    src = open(ah.__file__).read().lower()
    assert "checkout" not in src and "/submit" not in src and "placeorder" not in src
