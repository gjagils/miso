from app.api.routes import aggregate_cart
import pytest

from app.matching import choose, is_pantry, needed, pack_size, packs_for, query_terms, score
from app.models import Recipe


def test_amounts_and_packs():
    assert needed("250 g halloumi (in dikke plakken)") == {"amount": 250.0, "unit": "g", "spoon": False}
    assert needed("Halloumi 75 g")["amount"] == 75
    assert needed("½ bosje munt")["unit"] == "bos"
    assert packs_for(needed("250 g halloumi"), pack_size("225 g")) == 2
    assert packs_for(needed("500 g tomaten"), pack_size("1 kg")) == 1
    assert packs_for(needed("1 rode ui"), pack_size("per stuk")) == 1
    assert packs_for(needed("2 el sojasaus"), pack_size("250 ml")) == 1
    assert packs_for(needed("200 g rijst"), pack_size("3 stuks")) is None  # eenheden niet vergelijkbaar


def test_pantry_is_skipped():
    assert is_pantry("zeezoutvlokken en zwarte peper") and is_pantry("extra vergine olijfolie")
    assert not is_pantry("halloumi")


def test_choose_prefers_organic_then_house_brand_and_skips_candy():
    prods = [
        {"name": "Ricola Citroen munt suikervrij", "brand": "Ricola", "category": "Koek, snoep, chocolade"},
        {"name": "AH Munt", "brand": "AH", "category": "Groente"},
        {"name": "AH Biologisch Munt", "brand": "AH", "organic": True, "category": "Groente"},
    ]
    assert choose(prods, "munt")["name"] == "AH Biologisch Munt"
    assert choose([prods[0]], "munt") is None
    assert choose([{"name": "Dr. Oetker Kwarktaart citroensmaak bakmix", "brand": "Dr. Oetker"}], "citroen") is None


def test_cart_sums_amounts_across_recipes_before_rounding_packs():
    product = {"id": 7, "name": "AH Halloumi", "unit_size": "225 g"}
    need, pack = needed("100 g halloumi"), pack_size("225 g")
    ing = {"text": "100 g halloumi", "product": product, "quantity": 1, "need": need, "pack": pack}
    recipes = []
    for _ in range(3):
        r = Recipe(name="x")
        r.ingredients = [dict(ing)]
        recipes.append(r)
    cart, unmatched = aggregate_cart(recipes)
    assert cart[0]["quantity"] == 2 and unmatched == []  # 300 g -> 2 pakken (niet 3)


@pytest.mark.parametrize("text,query", [
    ("2 gele paprika's", "gele paprika"),
    ("350 g kippendijfilet", "kipdijfilet"),
    ("500 ml kippenbouillon van tablet", "bouillon kip"),
    ("1 vleesbouillontablet", "bouillon rund"),
    ("1 gedroogd laurierblaadje", "laurier"),
    ("Half-om-half gehakt 450 g", "half om half gehakt"),
    ("500 g half-om-halfgehakt", "half om half gehakt"),
    ("90 g parmaham", "prosciutto di parma"),
    ("2 druppels tabasco", "tabasco red pepper"),
    ("300 g mezzi rigatoni nr. 26", "mezzi rigatoni"),
    ("150 g Manchego kazen", "manchego"),
    ("400 g Italiaanse roerbakmix", "roerbakgroente italiaanse"),
    ("6 basilicumblaadjes", "basilicum"),
])
def test_query_normalisation_round6(text, query):
    assert query_terms(text)[0] == query


def test_spoon_of_herb_is_dried():
    assert "dried" in query_terms("3 tl dragon")[2]
    assert "fresh" in query_terms("10 g dragon")[2]


def test_diminutive_matches_product_title():
    p = {"name": "AH Verse granaatappelpitjes", "unit_size": "90 g", "category": "Groente, aardappelen"}
    q, _, flags = query_terms("100 g verse granaatappelpitjes")
    assert score(p, q, flags) >= 30
    radish = {"name": "AH Radijs", "unit_size": "200 g", "category": "Groente, aardappelen"}
    assert score(radish, *[query_terms("5 radijsjes")[i] for i in (0, 2)]) >= 30


def test_lean_adjective_first_is_not_other_product():
    p = {"name": "AH Mager spekblokjes", "unit_size": "250 g", "category": "Vlees, kip, vis, vega"}
    assert score(p, "spekblokjes") >= 30


def test_color_word_after_noun_in_title():
    p = {"name": "AH Paprika geel", "unit_size": "per stuk", "category": "Groente, aardappelen"}
    q, _, flags = query_terms("2 gele paprika's")
    assert score(p, q, flags) >= 30


@pytest.mark.parametrize("text,query", [
    ("1 kaneelstokje", "kaneel heel"),
    ("1 beker zure room", "sour cream"),
    ("1 pak quichedeeg", "quiche taartdeeg"),
    ("85 g geraspte oude kaas", "goudse oud geraspt"),
    ("2x gerookte kipreepjes", "gerookte kipfilet"),
    ("15 g verse krulpeterselie", "peterselie"),
])
def test_query_normalisation_round6b(text, query):
    assert query_terms(text)[0] == query


def _p(name, size="per stuk", cat="Groente, aardappelen"):
    return {"name": name, "unit_size": size, "category": cat}


@pytest.mark.parametrize("text,good,bad", [
    ("1 rode paprika", _p("AH Biologisch Paprika rood"), _p("AH Paprika rode reepjes 2-pack", "2 stuks")),
    ("400 g kikkererwten in blik", _p("AH Terra Kikkererwten", "400 g", "Soepen, conserven"),
     _p("AH Kikkererwten paprika", "100 g", "Soepen, conserven")),
    ("75g gedroogde cranberry's", _p("AH Cranberries", "200 g", "Ontbijtgranen en beleg"),
     _p("AH Cremepate cranberry", "150 g", "Vleeswaren, kaas en tapas")),
    ("85 g geraspte oude kaas", _p("AH Goudse oud 48+ geraspt", "175 g", "Kaas"),
     _p("AH Goudse oud 48+ stuk", "ca. 500 g", "Kaas")),
])
def test_round7_prefers_plain_product(text, good, bad):
    q, _, flags = query_terms(text)
    assert score(good, q, flags) > score(bad, q, flags)


def test_fresh_herbs_never_from_a_jar():
    q, _, flags = query_terms("20 g verse Italiaanse kruidenmix")
    assert score(_p("Verstegen Italiaanse kruiden", "12 g", "Soepen, sauzen, kruiden, olie"), q, flags) < 30


@pytest.mark.parametrize("text,query,flag", [
    ("2 eetlepels dille", "dille", "fresh"),
    ("1 tl dille", "dille", "dried"),
    ("6 salade-uien", "bosui", None),
    ("250 g kleine trostomaatjes aan de tak", "cherry trostomaten", None),
    ("2 el olijfolie extra vierge met truffelaroma", "olijfolie truffel", None),
])
def test_round8_normalisation(text, query, flag):
    q, _, flags = query_terms(text)
    assert q == query
    if flag:
        assert flag in flags


def test_round9_rules():
    q, _, flags = query_terms("2 zakjes Mexicaanse kruidenmix")
    assert score(_p("AH Biologisch Kruiden kamille", "20 stuks", "Koffie, thee"), q, flags) < 0
    q, _, flags = query_terms("2 zakjes Griekse kruidenmix")
    assert score(_p("Verstegen Italiaanse kruiden", "12 g", "Soepen, sauzen, kruiden, olie"), q, flags) < 30
    q, _, flags = query_terms("1 kaneelstokje")
    assert score(_p("Verstegen Kaneel heel", "20 g", "Soepen, sauzen, kruiden, olie") | {"brand": "Verstegen"}, q, flags) > \
        score(_p("AH Kaneel gemalen", "40 g", "Soepen, sauzen, kruiden, olie"), q, flags)
    q, _, flags = query_terms("4 ansjovisfilets")
    assert score(_p("AH Filet americain naturel", "150 g", "Vleeswaren"), q, flags) < 30
    assert needed("2x garnalen (ontdooid, 250g)")["amount"] == 500
    q, _, flags = query_terms("1 hele kip")
    assert score(_p("AH Kip knakworst", "200 g", "Vlees"), q, flags) < score(_p("AH Scharrel hele kip", "1,4 kg", "Vlees"), q, flags)
