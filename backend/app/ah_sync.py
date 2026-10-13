"""AH-datalaag: lokale kopie van boodschappenrondes, prijzen en bonusperiodes.

Schermen lezen uit de tabellen `ah_trips`, `ah_prices` en `ah_bonus_periods`; alleen `sync_trips` en
`record_bonus` praten met AH, en die halen alleen op wat we nog niet hebben. Alles hier is lezen bij AH
plus schrijven in onze eigen database. Nooit bestellen.
"""

import asyncio
import json
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.clients import ah_data as ahd
from app.logging_config import logger
from app.models import AHBonusPeriod, AHPrice, AHTrip
from app.planning import get_setting, set_setting

SYNC_STATUS = "ah_sync_status"
DEFAULT_WEEKS = 52
MAX_NEW_PER_RUN = 60  # bescherming tegen een eerste sync die honderden bonnen tegelijk ophaalt


def _num(v) -> float | None:
    """'3.79' | '3,79' | 3.79 -> 3.79; leeg/onzin -> None."""
    if v is None or v == "":
        return None
    try:
        return round(float(str(v).replace(",", ".")), 2)
    except ValueError:
        return None


# ── Boodschappenrondes ─────────────────────────────────────────────────


def _known(db: Session) -> set[tuple[str, str]]:
    return set(db.execute(select(AHTrip.source, AHTrip.external_id)).all())


def save_trip(db: Session, trip: dict) -> AHTrip | None:
    """Trip (vorm uit `clients.ah_data`) opslaan; bestaat hij al, dan niets doen."""
    key = (trip["source"], str(trip["external_id"]))
    row = db.execute(select(AHTrip).where(AHTrip.source == key[0], AHTrip.external_id == key[1])).scalar_one_or_none()
    if row:
        return None
    row = AHTrip(source=key[0], external_id=key[1], date=trip["date"], store=trip.get("store") or "",
                 total=trip.get("total"), discount=trip.get("discount"))
    row.lines = [{k: ln.get(k) for k in ("product_id", "name", "quantity", "unit_price", "amount", "bonus", "category")}
                 for ln in trip.get("lines") or []]
    db.add(row)
    return row


async def sync_trips(db: Session, since: date | None = None, max_new: int = MAX_NEW_PER_RUN) -> dict:
    """Nieuwe bestellingen en kassabonnen sinds `since` ophalen en opslaan. Bestaande ritten worden
    niet opnieuw opgehaald. Geeft {"added", "known", "errors", "orders", "receipts"} terug."""
    since = since or date.today() - timedelta(weeks=DEFAULT_WEEKS)
    known = _known(db)
    errors: list[str] = []
    added = {"bestelling": 0, "kassabon": 0}
    sem = asyncio.Semaphore(4)

    try:
        order_hdrs = [h for h in await ahd.order_headers(since) if ("bestelling", str(h["id"])) not in known]
    except ahd.AHDataError as e:
        errors.append(str(e))
        order_hdrs = []
    try:
        receipt_hdrs = [h for h in await ahd.receipt_headers(since, 200) if ("kassabon", str(h["id"])) not in known]
    except ahd.AHDataError as e:
        errors.append(str(e))
        receipt_hdrs = []
    order_hdrs, receipt_hdrs = order_hdrs[:max_new], receipt_hdrs[:max_new]

    async def order(h: dict) -> dict | None:
        async with sem:
            try:
                return await ahd.order_detail(h)
            except ahd.AHDataError as e:
                errors.append(f"bestelling {h['id']}: {e}")
                return None

    async def receipt(h: dict) -> dict | None:
        async with sem:
            try:
                return await ahd.receipt_detail(h)
            except ahd.AHDataError as e:
                errors.append(f"kassabon {h['id']}: {e}")
                return None

    orders = [t for t in await asyncio.gather(*(order(h) for h in order_hdrs)) if t]
    receipts = [t for t in await asyncio.gather(*(receipt(h) for h in receipt_hdrs)) if t]
    if receipts:
        try:
            receipts = await ahd.resolve_receipts(receipts)
        except ahd.AHDataError as e:
            errors.append(str(e))
            for t in receipts:  # dan zonder webshop-ids: namen en bedragen blijven bruikbaar
                for ln in t["lines"]:
                    ln.pop("pos_id", None)
                    ln.setdefault("product_id", 0)
    for trip in orders + receipts:
        if save_trip(db, trip):
            added[trip["source"]] += 1
    db.commit()
    result = {"added": sum(added.values()), "orders": added["bestelling"], "receipts": added["kassabon"],
              "known": len(known), "errors": errors[:10], "since": str(since)}
    status = {"last_run": datetime.now().isoformat(timespec="seconds"), "ok": not errors, **result,
              "trips_total": db.query(AHTrip).count()}
    set_setting(db, SYNC_STATUS, json.dumps(status, ensure_ascii=False))
    logger.info("AH-sync: %d nieuwe ritten (%d bestellingen, %d bonnen), %d fouten",
                result["added"], added["bestelling"], added["kassabon"], len(errors))
    return result


def sync_status(db: Session) -> dict:
    try:
        data = json.loads(get_setting(db, SYNC_STATUS) or "null")
    except ValueError:
        data = None
    data = data if isinstance(data, dict) else {"last_run": None, "ok": None}
    data["trips_total"] = db.query(AHTrip).count()
    data["prices_total"] = db.query(AHPrice).count()
    data["bonus_periods"] = db.query(AHBonusPeriod).count()
    return data


def trips_since(db: Session, since: date) -> list[AHTrip]:
    return list(db.execute(select(AHTrip).where(AHTrip.date >= str(since)).order_by(AHTrip.date.desc(), AHTrip.id.desc()))
                .scalars())


def trips_as_dicts(trips: list[AHTrip]) -> list[dict]:
    """Vorm die `clients.ah_data.compute_staples` en `replenish` verwachten."""
    out = []
    for t in trips:
        lines = t.lines
        out.append({"id": t.id, "source": t.source, "date": t.date, "store": t.store, "total": t.total,
                    "discount": t.discount, "lines": lines,
                    "products": {int(ln["product_id"]): ln.get("name", "") for ln in lines if ln.get("product_id")}})
    return out


# ── Prijzen ────────────────────────────────────────────────────────────


def record_prices(db: Session, products: list[dict], day: date | None = None, commit: bool = True) -> int:
    """Prijssnapshot van zoekresultaten/bonusproducten voor vandaag. Eén rij per product per dag."""
    day = str(day or date.today())
    todo: dict[int, dict] = {}
    for p in products or []:
        pid = ahd._int((p or {}).get("id") or (p or {}).get("product_id"))
        price = _num(p.get("price") if "price" in p else p.get("was"))
        if pid and price is not None:
            todo[pid] = p
    if not todo:
        return 0
    have = set(db.execute(select(AHPrice.product_id).where(AHPrice.date == day, AHPrice.product_id.in_(todo))).scalars())
    n = 0
    for pid, p in todo.items():
        if pid in have:
            continue
        db.add(AHPrice(product_id=pid, date=day, name=str(p.get("name") or p.get("title") or "")[:500],
                       price=_num(p.get("price") if "price" in p else p.get("was")),
                       bonus_price=_num(p.get("bonus_price") if "bonus_price" in p else p.get("now")),
                       mechanism=str(p.get("mechanism") or "")[:100], unit_size=str(p.get("unit_size") or "")[:100]))
        n += 1
    if n and commit:
        db.commit()
    return n


def latest_prices(db: Session, product_ids: list[int]) -> dict[int, AHPrice]:
    """Laatste snapshot per product."""
    ids = [int(i) for i in product_ids if i]
    if not ids:
        return {}
    rows = db.execute(select(AHPrice).where(AHPrice.product_id.in_(ids)).order_by(AHPrice.date)).scalars()
    return {r.product_id: r for r in rows}  # latere datum overschrijft eerdere


# ── Bonusperiodes ──────────────────────────────────────────────────────


def record_bonus(db: Session, fresh: dict, user: bool) -> AHBonusPeriod:
    """Resultaat van `clients.ah_data.fetch_bonus` opslaan (of vervangen) op startdatum."""
    row = db.execute(select(AHBonusPeriod).where(AHBonusPeriod.start == fresh["start"])).scalar_one_or_none()
    if not row:
        row = AHBonusPeriod(start=fresh["start"])
        db.add(row)
    row.end, row.user = fresh.get("end") or "", user
    row.personal, row.groups = int(fresh.get("personal") or 0), int(fresh.get("groups") or 0)
    row.products = fresh["products"]
    row.fetched_at = ahd.now_iso()
    # bonusprijzen zijn ook prijssnapshots (prijs zonder en met bonus)
    record_prices(db, [{"id": pid, "name": p.get("title"), "price": p.get("was"), "bonus_price": p.get("now"),
                        "mechanism": p.get("mechanism")} for pid, p in fresh["products"].items()],
                  day=date.fromisoformat(fresh["start"]) if fresh.get("start") else None, commit=False)
    db.commit()
    return row


def bonus_period(db: Session, day: date | None = None) -> AHBonusPeriod | None:
    """De bonusperiode waar `day` (default vandaag) in valt."""
    d = str(day or date.today())
    return db.execute(select(AHBonusPeriod).where(AHBonusPeriod.start <= d, AHBonusPeriod.end >= d)
                      .order_by(AHBonusPeriod.start.desc())).scalars().first()


def bonus_for_week(db: Session, monday: date) -> AHBonusPeriod | None:
    """Bonus die geldt in de week van `monday`: de periode die die maandag bevat, anders de dichtstbijzijnde
    die er vlak voor of na begint."""
    return bonus_period(db, monday) or db.execute(
        select(AHBonusPeriod).where(AHBonusPeriod.start >= str(monday - timedelta(days=6)),
                                    AHBonusPeriod.start <= str(monday + timedelta(days=6)))
        .order_by(AHBonusPeriod.start)).scalars().first()


# ── Dagelijkse ronde (aangeroepen door app.maintenance.daily_loop) ────────


async def run_daily_once() -> dict:
    """Eén ronde: ritten syncen en de bonus (deze en volgende week) verversen, als AH gekoppeld is."""
    from app.api.ah_data import get_bonus
    from app.api.shopping import _use_user_tokens
    from app.database import SessionLocal

    result: dict = {"synced": False, "bonus": False, "errors": []}
    with SessionLocal() as db:
        if _use_user_tokens(db):
            try:
                result["trips"] = await sync_trips(db)
                result["synced"] = True
            except Exception as e:  # noqa: BLE001
                result["errors"].append(f"sync: {e}")
        for period in ("current", "next"):
            try:
                await get_bonus(db, False, period)
                result["bonus"] = True
            except Exception as e:  # noqa: BLE001
                result["errors"].append(f"bonus {period}: {str(e)[:120]}")
    if result["errors"]:
        logger.info("AH dagelijkse sync met opmerkingen: %s", "; ".join(result["errors"])[:300])
    return result
