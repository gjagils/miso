"""Dagelijks onderhoud: back-up van de database en foto's, en gezondheidsprofielen voor nieuwe recepten.

Back-ups staan in data/backups (dezelfde schijf als de data): dit beschermt tegen fouten en een kapotte
database, niet tegen een kapotte NAS. Neem /volume1/docker/miso/data mee in Hyper Backup voor een kopie elders.
"""

import asyncio
import os
import sqlite3
import tarfile
from datetime import date

from sqlalchemy import select

from app.config import settings
from app.database import SessionLocal
from app.logging_config import logger

DATA_DIR = "data"
BACKUP_DIR = os.path.join(DATA_DIR, "backups")
KEEP_DB = 14  # dagen
KEEP_IMAGES = 2  # weken


def _db_path() -> str | None:
    url = settings.database_url
    return url.split("sqlite:///", 1)[1] if url.startswith("sqlite:///") else None


def _prune(prefix: str, keep: int) -> None:
    files = sorted(f for f in os.listdir(BACKUP_DIR) if f.startswith(prefix))
    for old in files[:-keep]:
        os.remove(os.path.join(BACKUP_DIR, old))


def backup_now(today: date | None = None) -> list[str]:
    """Maak (hooguit één per dag) een kopie van de database; wekelijks ook de foto's. Geeft nieuwe bestanden."""
    today = today or date.today()
    src = _db_path()
    if not src or not os.path.exists(src):
        return []
    os.makedirs(BACKUP_DIR, exist_ok=True)
    made = []
    target = os.path.join(BACKUP_DIR, f"miso-{today.isoformat()}.db")
    if not os.path.exists(target):
        with sqlite3.connect(src) as live, sqlite3.connect(target) as copy:
            live.backup(copy)  # consistente kopie, ook terwijl de app schrijft
        made.append(target)
        _prune("miso-", KEEP_DB)
    images = os.path.join(DATA_DIR, "images")
    year, week, _ = today.isocalendar()
    tar = os.path.join(BACKUP_DIR, f"images-{year}-W{week:02d}.tar.gz")
    if os.path.isdir(images) and not os.path.exists(tar):
        with tarfile.open(tar, "w:gz") as t:
            t.add(images, arcname="images")
        made.append(tar)
        _prune("images-", KEEP_IMAGES)
    return made


async def profile_missing() -> int:
    """Gezondheidsprofiel voor recepten die er nog geen hebben, zodat 'Laat Miso voorstellen' alles meeneemt."""
    if not settings.anthropic_api_key:
        return 0
    from app.models import Recipe
    from app.nutrition import ensure_profile, get_profile

    done = 0
    with SessionLocal() as db:
        for recipe in db.execute(select(Recipe)).scalars().all():
            if get_profile(db, recipe.id) is None and await ensure_profile(db, recipe):
                done += 1
                await asyncio.sleep(1)  # rustig aan met de Claude-API
    return done


async def daily_loop() -> None:
    await asyncio.sleep(60)  # eerst de app laten opstarten
    while True:
        try:
            made = await asyncio.to_thread(backup_now)
            if made:
                logger.info("Back-up gemaakt: %s", ", ".join(os.path.basename(m) for m in made))
            n = await profile_missing()
            if n:
                logger.info("Gezondheidsprofiel gemaakt voor %d recepten", n)
            await monthly_packs()
            n = await localize_photos()
            if n:
                logger.info("Foto lokaal bewaard voor %d recepten", n)
        except Exception as e:  # noqa: BLE001 - onderhoud mag de app nooit laten vallen
            logger.warning("Dagelijks onderhoud mislukt: %s", e)
        await asyncio.sleep(24 * 3600)


async def profile_one(recipe_id: int) -> None:
    """Profiel voor één (net geïmporteerd) recept, op de achtergrond."""
    if not settings.anthropic_api_key:
        return
    from app.models import Recipe
    from app.nutrition import ensure_profile

    try:
        with SessionLocal() as db:
            recipe = db.get(Recipe, recipe_id)
            if recipe:
                await ensure_profile(db, recipe)
    except Exception as e:  # noqa: BLE001
        logger.warning("Profiel voor recept %s mislukt: %s", recipe_id, e)


def profile_later(recipe_id: int) -> None:
    try:
        asyncio.get_running_loop().create_task(profile_one(recipe_id))
    except RuntimeError:
        pass  # geen event loop (tests)


async def localize_photos() -> int:
    """Recepten met een externe foto-link: foto ophalen en lokaal bewaren (eenmalig per recept)."""
    from app.api.routes import store_photo_locally
    from app.models import Recipe

    done = 0
    with SessionLocal() as db:
        for recipe in db.execute(select(Recipe).where(Recipe.image_url.like("http%"))).scalars().all():
            if await store_photo_locally(db, recipe):
                done += 1
            await asyncio.sleep(0.5)
    return done


async def monthly_packs() -> None:
    """Maaltijdpakketten eens per ~maand bijwerken: AH wisselt het assortiment en de samenstelling."""
    from datetime import date

    from app import packs
    from app.api.routes import _get_setting

    with SessionLocal() as db:
        last = _get_setting(db, "packs_synced_on")
        if last and (date.today() - date.fromisoformat(last)).days < 28:
            return
        result = await packs.sync(db)
    logger.info("Maaltijdpakketten bijgewerkt: %s nieuw, %s bijgewerkt, %s opgeruimd",
                result["new"], result["updated"], result["archived"])
