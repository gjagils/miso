"""Bonushint (A5): hoeveel eigen recepten zitten volgende week in de bonus."""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app import ah_sync, bonushint
from app.api import routes
from app.main import app
from tests.test_routes import _ing, _recipe, db  # noqa: F401  (fixture)


def _next_monday():
    return routes.monday_of(date.today()) + timedelta(days=7)


def _bonus(db, monday, products):  # noqa: F811
    ah_sync.record_bonus(db, {"start": str(monday), "end": str(monday + timedelta(days=6)), "personal": 0, "groups": 0,
                              "products": products}, False)


def test_no_bonus_known_gives_empty_hint(db):  # noqa: F811
    _recipe(db, "Pasta", [_ing("pasta", 1)])
    assert bonushint.next_week(db) == {"count": 0, "saving": 0, "names": [], "message": ""}


def test_hint_lists_best_recipes_first(db):  # noqa: F811
    _recipe(db, "Garnalen met rijst", [_ing("garnalen", 3), _ing("rijst", 1)])
    _recipe(db, "Kip met rijst", [_ing("kip", 2), _ing("rijst", 1)])
    _recipe(db, "Pasta pesto", [_ing("pasta", 4), _ing("pesto", 5)])
    _bonus(db, _next_monday(), {3: {"id": 3, "title": "Garnalen", "now": 4.0, "was": 6.0, "saving": 2.0, "mechanism": "33%"},
                                2: {"id": 2, "title": "Kip", "now": 3.0, "was": 4.0, "saving": 1.0, "mechanism": "25%"}})
    hint = bonushint.next_week(db)
    assert hint["count"] == 2 and hint["names"] == ["Garnalen met rijst", "Kip met rijst"]
    assert hint["saving"] == 3.0
    assert hint["message"] == ("2 recepten van jullie zitten volgende week in de bonus (samen ongeveer €3,00 voordeel): "
                               "Garnalen met rijst en Kip met rijst.")


def test_hint_in_next_week_status_and_banner(db):  # noqa: F811
    _recipe(db, "Garnalen met rijst", [_ing("garnalen", 3)])
    _bonus(db, _next_monday(), {3: {"id": 3, "title": "Garnalen", "now": 4.0, "was": 6.0, "saving": 2.0, "mechanism": "33%"}})
    client = TestClient(app)
    status = client.get("/api/plan/next-week-status").json()
    assert status["bonus_hint"]["count"] == 1 and "1 recept van jullie zit volgende week in de bonus" in status["bonus_hint"]["message"]
    assert "zit volgende week in de bonus" in client.get("/weekmenu").text


def test_tiny_savings_do_not_count(db):  # noqa: F811
    _recipe(db, "Garnalen met rijst", [_ing("garnalen", 3)])
    _bonus(db, _next_monday(), {3: {"id": 3, "title": "Garnalen", "now": 5.9, "was": 6.0, "saving": 0.1, "mechanism": "2%"}})
    assert bonushint.next_week(db)["count"] == 0
