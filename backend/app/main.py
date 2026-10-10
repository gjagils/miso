import asyncio
import hashlib
import hmac
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from app.api.ah_data import router as ah_data_router
from app.api.json_api import router as json_router
from app.api.routes import router
from app.api.shopping import router as shopping_router
from app.api.health import router as health_router
from app.api.plan import router as plan_router
from app.api.wishes import router as wishes_router
from app.api.family import router as family_router
from app.config import settings
from app.database import Base, engine
from app.logging_config import setup_logging
from app.migrations import migrate

setup_logging()
Base.metadata.create_all(engine)
migrate(engine)


def _encrypt_tokens() -> None:
    from app.database import SessionLocal
    from app.logging_config import logger
    from app.secretbox import encrypt_existing

    with SessionLocal() as db:
        n = encrypt_existing(db)
    if n:
        logger.info("%d geheime instellingen versleuteld", n)


_encrypt_tokens()

@asynccontextmanager
async def lifespan(app_: FastAPI):
    from app.maintenance import daily_loop

    task = asyncio.create_task(daily_loop())  # back-up + gezondheidsprofielen, elke 24 uur
    yield
    task.cancel()


app = FastAPI(title="Miso", version="1.1.0", lifespan=lifespan)

PUBLIC_PREFIXES = ("/login", "/api/login", "/static", "/image", "/favicon.ico")


def session_token() -> str:
    return hmac.new(settings.app_pin.encode(), b"ahrecepten-session", hashlib.sha256).hexdigest()


@app.middleware("http")
async def require_pin(request: Request, call_next):
    if settings.app_pin and not request.url.path.startswith(PUBLIC_PREFIXES):
        supplied = request.cookies.get("session", "")
        auth = request.headers.get("authorization", "")
        if auth.lower().startswith("bearer "):
            supplied = auth[7:].strip()
        if not hmac.compare_digest(supplied, session_token()):
            if request.url.path.startswith("/api/"):
                from fastapi.responses import JSONResponse

                return JSONResponse({"ok": False, "error": "Niet ingelogd"}, status_code=401)
            return RedirectResponse("/login", status_code=303)
    from app.api.family import kid_blocked

    if kid_blocked(request):  # kinderen: wensen en favorieten ja, wissen/bestellen/beheer nee
        from fastapi.responses import JSONResponse

        return JSONResponse({"ok": False, "error": "Vraag dit even aan papa of mama."}, status_code=403)
    return await call_next(request)


app.mount("/static", StaticFiles(directory="app/static"), name="static")


@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return FileResponse("app/static/favicon.ico", headers={"Cache-Control": "public, max-age=604800"})
app.include_router(ah_data_router)
app.include_router(json_router)
app.include_router(shopping_router)
app.include_router(health_router)
app.include_router(plan_router)
app.include_router(wishes_router)
app.include_router(family_router)
app.include_router(router)
