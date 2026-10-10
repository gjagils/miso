"""Versleuteling van geheime instellingen (AH-tokens, Mealie-token) in de database.

Sleutel: omgevingsvariabele MISO_SECRET (een lange willekeurige tekst). Zonder MISO_SECRET blijft alles leesbaar
opgeslagen, zoals voorheen. Versleutelde waarden beginnen met "enc:v1:". Raak je MISO_SECRET kwijt, dan
moet je AH opnieuw koppelen (de rest van de app werkt gewoon).
"""

import base64
import hashlib
import os

from cryptography.fernet import Fernet, InvalidToken

SECRET_KEYS = {"ah_user_token", "ah_refresh_token", "mealie_token"}
PREFIX = "enc:v1:"


def _fernet() -> Fernet | None:
    secret = os.environ.get("MISO_SECRET", "").strip()
    if not secret:
        return None
    return Fernet(base64.urlsafe_b64encode(hashlib.sha256(secret.encode()).digest()))


def seal(key: str, value: str) -> str:
    f = _fernet()
    if key not in SECRET_KEYS or not value or not f or value.startswith(PREFIX):
        return value
    return PREFIX + f.encrypt(value.encode()).decode()


def unseal(key: str, value: str) -> str:
    if not value or not value.startswith(PREFIX):
        return value
    f = _fernet()
    if not f:
        return ""  # versleuteld maar geen sleutel: behandel als niet gekoppeld
    try:
        return f.decrypt(value[len(PREFIX):].encode()).decode()
    except InvalidToken:
        return ""  # andere sleutel: opnieuw koppelen


def encrypt_existing(db) -> int:
    """Eenmalig bij opstarten: nog leesbare geheime waarden versleutelen (als MISO_SECRET gezet is)."""
    from sqlalchemy import select

    from app.models import AppSetting

    if not _fernet():
        return 0
    done = 0
    for row in db.execute(select(AppSetting).where(AppSetting.key.in_(SECRET_KEYS))).scalars():
        if row.value and not row.value.startswith(PREFIX):
            row.value = seal(row.key, row.value)
            done += 1
    db.commit()
    return done
