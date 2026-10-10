"""Pincode raden afremmen nu Miso via internet bereikbaar is (miso.gerdjan.nl achter Cloudflare).

Per adres: na 10 foute pogingen 15 minuten geen nieuwe poging. Over alle adressen samen: na 50 foute
pogingen in 15 minuten even helemaal niet (tegen raden vanaf veel adressen). Wie al ingelogd is, merkt
er niets van: het sessietoken blijft gewoon werken.
"""

import time

from fastapi import Request

WINDOW_S = 15 * 60
PER_IP = 10
GLOBAL = 50
_fails: dict[str, list[float]] = {}


def client_ip(request: Request) -> str:
    return (request.headers.get("cf-connecting-ip") or request.headers.get("x-forwarded-for", "").split(",")[0].strip()
            or (request.client.host if request.client else "?"))


def _recent(key: str, now: float) -> list[float]:
    hits = [t for t in _fails.get(key, []) if now - t < WINDOW_S]
    _fails[key] = hits
    return hits


def blocked(request: Request) -> bool:
    now = time.monotonic()
    return len(_recent(client_ip(request), now)) >= PER_IP or len(_recent("*", now)) >= GLOBAL


def failed(request: Request) -> None:
    now = time.monotonic()
    for key in (client_ip(request), "*"):
        _fails.setdefault(key, []).append(now)


def succeeded(request: Request) -> None:
    _fails.pop(client_ip(request), None)


BLOCKED_TEXT = "Te veel foute pogingen. Probeer het over een kwartier opnieuw."
