"""Wie ben jij?, favorieten/wensen per persoon en de kinderrol."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import sessionmaker

from app import database
from app.api import family
from app.main import app
from app.models import RecipeFavorite, Wish
from tests.test_routes import _recipe, db  # noqa: F401  (fixture)


@pytest.fixture()
def fam(db, monkeypatch):
    factory = sessionmaker(bind=db.get_bind())
    monkeypatch.setattr(database, "SessionLocal", factory)
    monkeypatch.setattr(family, "SessionLocal", factory)
    return db


def test_who_page_and_per_person_favorites(fam):
    r = _recipe(fam, "Spaghetti gehaktballetjes", [])
    client = TestClient(app)
    assert "Hannah" in client.get("/wie").text and "Suze" in client.get("/wie").text
    client.post("/wie", data={"member": "hannah"}, follow_redirects=False)
    assert client.cookies.get("miso_member") == "hannah"
    out = client.patch(f"/api/recipes/{r.id}/flags", json={"favorite": True}).json()
    assert out["recipe"]["favorite"] and out["recipe"]["fans"] == ["H"]
    client.cookies.set("miso_member", "suze")
    out = client.patch(f"/api/recipes/{r.id}/flags", json={"favorite": True}).json()
    assert sorted(out["recipe"]["fans"]) == ["H", "S"]
    out = client.patch(f"/api/recipes/{r.id}/flags", json={"favorite": False}).json()
    assert out["recipe"]["fans"] == ["H"] and out["recipe"]["favorite"]  # Hannah vindt hem nog lekker
    assert fam.query(RecipeFavorite).count() == 1


def test_kid_wishes_but_cannot_delete(fam):
    r = _recipe(fam, "Pannenkoeken", [])
    client = TestClient(app)
    client.cookies.set("miso_member", "suze")
    assert client.post("/api/wishes", json={"recipe_id": r.id}).json()["wishes"][0]["member"] == "Suze"
    assert client.post("/api/wishes", json={"text": "iets met wraps"}).json()["ok"]
    assert client.delete(f"/api/recipes/{r.id}").status_code == 403
    assert client.post("/api/plan/sync", json={}).status_code == 403
    assert client.patch(f"/api/recipes/{r.id}/flags", json={"archived": True}).status_code == 403
    assert "Wat wil jij graag eten, Suze?" in client.get("/plannen").text
    client.cookies.set("miso_member", "gerd-jan")
    page = client.get("/plannen").text
    assert "Wensen van het gezin" in page and "Suze" in page and "iets met wraps" in page
    assert fam.query(Wish).count() == 2


def test_members_are_editable(fam):
    client = TestClient(app)
    out = client.put("/api/members", json={"members": [{"name": "Gerd-Jan", "role": "ouder"}, {"name": "Hannah", "role": "kind"}]}).json()
    assert [m["name"] for m in out["members"]] == ["Gerd-Jan", "Hannah"] and out["members"][1]["role"] == "kind"


def test_grocery_wish_to_list(fam, monkeypatch):
    from app.api import routes

    client = TestClient(app)
    client.cookies.set("miso_member", "hannah")
    w = client.post("/api/wishes", json={"text": "koekjes", "kind": "boodschap"}).json()["wishes"][0]
    assert w["kind"] == "boodschap"
    assert client.post(f"/api/wishes/{w['id']}/to-list").status_code == 403  # kind zet niets op het lijstje

    async def fake_extras(db, extras):
        return [{"text": "koekjes", "product": {"id": 77, "name": "AH Stroopwafels"}}]

    monkeypatch.setattr(routes, "match_extras", fake_extras)
    client.cookies.set("miso_member", "nelleke")
    assert "koekjes" in client.get("/plannen").text
    out = client.post(f"/api/wishes/{w['id']}/to-list").json()
    assert out["ok"] and out["product"] == "AH Stroopwafels" and "p=77" in out["url"] and out["wishes"] == []


def test_avatar_upload_private(fam, tmp_path, monkeypatch):
    import io

    from PIL import Image

    from app import members

    monkeypatch.setattr(members, "AVATAR_DIR", str(tmp_path))
    buf = io.BytesIO()
    Image.new("RGBA", (300, 400), (255, 0, 0, 255)).save(buf, format="PNG")
    client = TestClient(app)
    out = client.post("/api/members/hannah/avatar", files={"photo": ("h.png", buf.getvalue(), "image/png")}).json()
    assert out["ok"] and out["avatar_url"].startswith("/avatar/hannah?v=")
    assert client.get("/avatar/hannah").status_code == 200
    assert any(m["avatar_url"] for m in client.get("/api/members").json()["members"])
    assert "/avatar/" not in __import__("app.main", fromlist=["PUBLIC_PREFIXES"]).PUBLIC_PREFIXES  # achter de pincode
