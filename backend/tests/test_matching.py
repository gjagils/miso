from app.api.routes import aggregate_cart
from app.matching import choose, is_pantry, needed, pack_size, packs_for
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
