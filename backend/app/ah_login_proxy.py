"""Eenmalige AH-inlogproxy.

AH stuurt na het inloggen door naar ``appie://login-exit?code=...``; een browser kan die link niet
openen. Deze kleine app proxyt ``login.ah.nl`` en schrijft die redirect om naar ``/callback``,
zodat de code hier terechtkomt, wordt omgewisseld voor tokens en in de instellingen wordt bewaard.

Draait als losse service op een eigen poort (zie docker-compose.yml). Inloggen en de sms-code doe je
zelf in de browser; er wordt geen wachtwoord door Miso bewaard.
"""

import hashlib
import hmac
import logging
from urllib.parse import parse_qs, urlsplit

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import select

from app.clients.ah import ah_client
from app.config import settings
from app.database import Base, SessionLocal, engine
from app.models import AppSetting

logger = logging.getLogger("ahcommunicator")

UPSTREAM = "https://login.ah.nl"
APPIE_REDIRECT = "appie://login-exit"
LOGIN_PATH = "/login?client_id=appie&redirect_uri=appie://login-exit&response_type=code"
COOKIE = "miso_setup"

# Antwoordheaders die de proxy breken (of niet meer kloppen na het herschrijven)
DROP_RESPONSE_HEADERS = {
    "content-security-policy", "content-security-policy-report-only", "strict-transport-security",
    "x-frame-options", "content-encoding", "content-length", "transfer-encoding", "connection",
}
DROP_REQUEST_HEADERS = {"host", "content-length", "accept-encoding", "connection", "origin", "referer"}
TEXT_TYPES = ("text/", "application/json", "application/javascript", "application/x-javascript")

Base.metadata.create_all(engine)
app = FastAPI(title="Miso AH-login")


def _setup_token() -> str:
    return hmac.new(settings.app_pin.encode(), b"miso-ah-setup", hashlib.sha256).hexdigest()


def _authorized(request: Request) -> bool:
    if not settings.app_pin:
        return True
    return hmac.compare_digest(request.cookies.get(COOKIE, ""), _setup_token())


def _origin(request: Request) -> str:
    return f"{request.url.scheme}://{request.headers.get('host', request.url.netloc)}"


def _set_setting(key: str, value: str) -> None:
    with SessionLocal() as db:
        row = db.execute(select(AppSetting).where(AppSetting.key == key)).scalar_one_or_none()
        if row:
            row.value = value
        else:
            db.add(AppSetting(key=key, value=value))
        db.commit()


def _page(body: str, status: int = 200) -> HTMLResponse:
    html = f"""<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Miso – AH koppelen</title>
<body style="font-family:system-ui;background:#FFF6E8;color:#0E2A47;max-width:420px;margin:12vh auto;padding:0 20px">
<h1 style="color:#0E2A47">Miso</h1>{body}"""
    return HTMLResponse(html, status_code=status)


@app.get("/start")
async def start_form():
    return _page(
        "<p>Voer de pincode van het gezin in om je AH-account te koppelen.</p>"
        '<form method=post action="/start"><input name=pin type=password inputmode=numeric autofocus '
        'style="font-size:20px;padding:10px;width:100%;box-sizing:border-box">'
        '<button style="margin-top:12px;font-size:18px;padding:10px 18px;background:#FF8A00;border:0;'
        'border-radius:10px;color:#fff">Verder naar AH</button></form>'
    )


@app.post("/start")
async def start_submit(request: Request):
    form = parse_qs((await request.body()).decode())
    pin = (form.get("pin") or [""])[0].strip()
    if settings.app_pin and not hmac.compare_digest(pin, settings.app_pin):
        return _page("<p>Pincode klopt niet.</p><p><a href=/start>Opnieuw</a></p>", 401)
    resp = RedirectResponse(LOGIN_PATH, status_code=303)
    resp.set_cookie(COOKIE, _setup_token(), httponly=True, max_age=900)
    return resp


@app.get("/callback")
async def callback(request: Request):
    if not _authorized(request):
        return RedirectResponse("/start", status_code=303)
    code = request.query_params.get("code", "")
    if not code:
        return _page("<p>Geen code ontvangen van AH. Probeer het opnieuw via <a href=/start>/start</a>.</p>", 400)
    try:
        data = await ah_client.exchange_code(code)
        _set_setting("ah_user_token", data["access_token"])
        _set_setting("ah_refresh_token", data["refresh_token"])
    except Exception as e:  # noqa: BLE001
        logger.error("AH login via proxy failed: %s", e)
        return _page(f"<p>Koppelen mislukt: {e}</p><p><a href=/start>Opnieuw proberen</a></p>", 502)
    logger.info("AH account linked via login proxy")
    return _page("<h2>Gekoppeld ✅</h2><p>Je AH-account is gekoppeld aan Miso. Je kunt dit venster sluiten.</p>")


def _rewrite_text(text: str, origin: str) -> str:
    return text.replace(APPIE_REDIRECT, f"{origin}/callback").replace(UPSTREAM, origin)


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def proxy(path: str, request: Request):
    if not _authorized(request):
        return RedirectResponse("/start", status_code=303)

    origin = _origin(request)
    headers = {k: v for k, v in request.headers.items() if k.lower() not in DROP_REQUEST_HEADERS}
    headers["accept-encoding"] = "identity"
    headers["origin"] = UPSTREAM
    if "referer" in request.headers:
        headers["referer"] = request.headers["referer"].replace(origin, UPSTREAM)
    if "cookie" in headers:
        headers["cookie"] = "; ".join(
            c for c in headers["cookie"].split("; ") if not c.startswith(f"{COOKIE}=")
        )
    url = f"{UPSTREAM}/{path}" + (f"?{request.url.query}" if request.url.query else "")

    async with httpx.AsyncClient(follow_redirects=False, timeout=30) as client:
        upstream = await client.request(request.method, url, headers=headers, content=await request.body())

    out_headers: list[tuple[str, str]] = []
    for name, value in upstream.headers.multi_items():
        lname = name.lower()
        if lname in DROP_RESPONSE_HEADERS:
            continue
        if lname == "location":
            value = _rewrite_text(value, origin)
        elif lname == "set-cookie":
            parts = [p for p in value.split(";") if p.strip().lower() not in ("secure",)
                     and not p.strip().lower().startswith(("samesite", "domain"))]
            value = ";".join(parts)
        out_headers.append((name, value))

    content = upstream.content
    ctype = upstream.headers.get("content-type", "")
    if ctype.startswith(TEXT_TYPES):
        content = _rewrite_text(upstream.text, origin).encode()

    response = Response(content=content, status_code=upstream.status_code)
    for name, value in out_headers:
        response.headers.append(name, value)
    return response
