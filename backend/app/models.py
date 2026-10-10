import json
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Recipe(Base):
    __tablename__ = "recipes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(500))
    description: Mapped[str] = mapped_column(Text, default="")
    servings: Mapped[str] = mapped_column(String(100), default="")
    total_time: Mapped[str] = mapped_column(String(100), default="")
    source_url: Mapped[str] = mapped_column(Text, default="")
    # id of the recipe in Allerhande when added from there (prevents duplicates)
    ah_recipe_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    # slug of the recipe in Mealie when imported from there (prevents duplicates)
    mealie_slug: Mapped[str | None] = mapped_column(String(500), nullable=True, index=True)
    image_url: Mapped[str] = mapped_column(Text, default="")
    # Glutenvrij voor minstens 1 persoon: "none" | "extra" (extra glutenvrij product erbij)
    # | "replace" (ingrediënt voor iedereen vervangen)
    gf_mode: Mapped[str] = mapped_column(String(10), default="none")
    gf_note: Mapped[str] = mapped_column(Text, default="")
    # JSON list of {"text", "search", "skip", "quantity", "product": {...}|None,
    #               "gluten": bool, "gf_search": str, "gf_product": {...}|None}
    ingredients_json: Mapped[str] = mapped_column(Text, default="[]")
    # JSON list of strings
    instructions_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    # Gebruik en voorkeur (zie app/usage.py)
    favorite: Mapped[bool] = mapped_column(Boolean, default=False)
    archived: Mapped[bool] = mapped_column(Boolean, default=False)  # opgeruimd: niet in lijsten/voorstellen
    by_heart: Mapped[bool] = mapped_column(Boolean, default=False)  # "ken ik uit mijn hoofd": alleen voor boodschappen
    thumbs_up: Mapped[int] = mapped_column(Integer, default=0)
    thumbs_down: Mapped[int] = mapped_column(Integer, default=0)
    cooked_count: Mapped[int] = mapped_column(Integer, default=0)
    last_cooked: Mapped[str | None] = mapped_column(String(10), nullable=True)
    swapped_count: Mapped[int] = mapped_column(Integer, default=0)  # voorstel weggewisseld
    reviewed_on: Mapped[str | None] = mapped_column(String(10), nullable=True)  # bewust bewaard bij opruimen

    @property
    def ingredients(self) -> list[dict]:
        return json.loads(self.ingredients_json or "[]")

    @ingredients.setter
    def ingredients(self, value: list[dict]) -> None:
        self.ingredients_json = json.dumps(value, ensure_ascii=False)

    @property
    def instructions(self) -> list[str]:
        return json.loads(self.instructions_json or "[]")

    @instructions.setter
    def instructions(self, value: list[str]) -> None:
        self.instructions_json = json.dumps(value, ensure_ascii=False)


PLAN_KINDS = ("recipe", "leftover", "stock")


class PlanEntry(Base):
    """Eén avondeten op een datum.

    kind "recipe": recept koken (boodschappen voor `persons`, x2 als `cook_double` gezet is);
    kind "leftover": rest van het recept van `source_entry_id` (geen boodschappen);
    kind "stock": "hebben we al" / uit de vriezer (`text`), met optionele extra boodschappen (`extras`).
    `recipe_id` is 0 als er geen recept bij hoort (bestaande tabel heeft NOT NULL op die kolom).
    Nieuwe kolommen worden in bestaande databases toegevoegd door `app.migrations`.
    """

    __tablename__ = "plan_entries"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    date: Mapped[str] = mapped_column(String(10), index=True)  # YYYY-MM-DD
    recipe_id: Mapped[int] = mapped_column(Integer, index=True, default=0)
    kind: Mapped[str] = mapped_column(String(10), default="recipe", server_default="recipe")
    persons: Mapped[int | None] = mapped_column(Integer, nullable=True)  # None = huishoudgrootte
    text: Mapped[str] = mapped_column(Text, default="", server_default="")
    # JSON list of {"text", "product": {...}|None}
    extras_json: Mapped[str] = mapped_column(Text, default="[]", server_default="[]")
    source_entry_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    # naam van het vriezer-item waar deze voorraaddag een portie van nam (zodat verwijderen hem teruglegt)
    freezer_name: Mapped[str | None] = mapped_column(String(300), nullable=True)
    cook_double: Mapped[str | None] = mapped_column(String(10), nullable=True)  # "tomorrow" | "freezer"

    @property
    def extras(self) -> list[dict]:
        try:
            value = json.loads(self.extras_json or "[]")
        except ValueError:
            return []
        return value if isinstance(value, list) else []

    @extras.setter
    def extras(self, value: list[dict]) -> None:
        self.extras_json = json.dumps(value, ensure_ascii=False)


class FreezerItem(Base):
    """Wat er in de vriezer ligt (simpel: naam + porties)."""

    __tablename__ = "freezer_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(300))
    portions: Mapped[int] = mapped_column(Integer, default=1)
    added_on: Mapped[str] = mapped_column(String(10), default="")  # YYYY-MM-DD
    from_recipe_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    source_entry_id: Mapped[int | None] = mapped_column(Integer, nullable=True)  # kookdag bij "kook dubbel"


class CartPush(Base):
    """What we already put on the AH shopping list for a given week."""

    __tablename__ = "cart_pushes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    week_start: Mapped[str] = mapped_column(String(10), index=True)
    product_id: Mapped[int] = mapped_column(Integer)
    quantity: Mapped[int] = mapped_column(Integer, default=0)
    name: Mapped[str] = mapped_column(String(500), default="")


class AppSetting(Base):
    __tablename__ = "settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    key: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    value: Mapped[str] = mapped_column(Text, default="")


class ProductPreference(Base):
    """Geleerde keuze: voor deze zoekterm kiest het gezin dit AH-product (uit handmatige correcties)."""

    __tablename__ = "product_preferences"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    term: Mapped[str] = mapped_column(String(300), unique=True, index=True)
    product_json: Mapped[str] = mapped_column(Text, default="{}")
    uses: Mapped[int] = mapped_column(Integer, default=1)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class BasketPush(Base):
    """Wat Miso in het AH-mandje heeft gezet, zodat 'mandje leegmaken' alleen dat weghaalt."""

    __tablename__ = "basket_pushes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    product_id: Mapped[int] = mapped_column(Integer, index=True)
    quantity: Mapped[int] = mapped_column(Integer, default=0)
    name: Mapped[str] = mapped_column(String(500), default="")
    order_id: Mapped[str | None] = mapped_column(String(60), nullable=True)  # bij welke AH-bestelling


class RecipeProfile(Base):
    """Geschat gezondheids-/variatieprofiel per recept (kcal, groente, eiwitbron, basis, keuken, Schijf van Vijf)."""

    __tablename__ = "recipe_profiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    recipe_id: Mapped[int] = mapped_column(Integer, unique=True, index=True)
    profile_json: Mapped[str] = mapped_column(Text, default="{}")
    version: Mapped[int] = mapped_column(Integer, default=1)
