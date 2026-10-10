"""Welk Claude-model? Relatief instellen, zodat Miso meegaat als Anthropic nieuwe modellen uitbrengt.

Twee niveaus:
- "slim" (ANTHROPIC_MODEL, standaard "sonnet"): recepten uitlezen uit foto's en rommelige pagina's.
- "snel" (ANTHROPIC_MODEL_FAST, standaard "haiku"): korte JSON-taken (gezondheidsprofiel, glutenvrij, wensen).

Waarde = een familie ("haiku", "sonnet", "opus"): Miso kiest via de Models API het nieuwste model van die familie
(dagelijks opnieuw bekeken). Waarde die met "claude-" begint = precies dat model (vastzetten).
Lukt opzoeken niet, dan een bekend model als terugval.
"""

import time

import anthropic

from app.config import settings
from app.logging_config import logger

FALLBACK = {"slim": "claude-sonnet-5-5", "snel": "claude-haiku-4-5"}
DEFAULT_FAMILY = {"slim": "sonnet", "snel": "haiku"}
REFRESH_S = 24 * 3600
_cache: dict[str, tuple[float, str]] = {}


def _setting(tier: str) -> str:
    raw = settings.anthropic_model if tier == "slim" else settings.anthropic_model_fast
    return (raw or "").strip().lower() or DEFAULT_FAMILY[tier]


def newest_in_family(models: list, family: str) -> str | None:
    """Nieuwste model (op created_at) waarvan de id de familie bevat, bijv. 'haiku' -> claude-haiku-4-5."""
    hits = [m for m in models if f"-{family}" in m.id]
    return max(hits, key=lambda m: m.created_at).id if hits else None


async def model(tier: str) -> str:
    value = _setting(tier)
    if value.startswith("claude-"):
        return value  # vastgezet
    hit = _cache.get(value)
    if hit and time.monotonic() - hit[0] < REFRESH_S:
        return hit[1]
    try:
        client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        models = [m async for m in client.models.list(limit=100)]
        chosen = newest_in_family(models, value)
    except Exception as e:  # noqa: BLE001 - dan de terugval
        logger.warning("Claude-modellen opvragen mislukt (%s), terugval %s", e, FALLBACK[tier])
        chosen = None
    chosen = chosen or (hit[1] if hit else FALLBACK[tier])
    if not hit or hit[1] != chosen:
        logger.info("Claude-model voor '%s' (%s): %s", tier, value, chosen)
    _cache[value] = (time.monotonic(), chosen)
    return chosen
