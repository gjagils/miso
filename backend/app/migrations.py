"""Kleine, idempotente schema-migraties voor de bestaande SQLite-database.

`Base.metadata.create_all` maakt nieuwe tabellen, maar voegt geen kolommen toe aan bestaande tabellen.
Hier staan de kolommen die later zijn bijgekomen; ontbrekende kolommen worden met ALTER TABLE toegevoegd.
"""

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

from app.logging_config import logger

# tabel -> {kolom: SQL-definitie voor ALTER TABLE ... ADD COLUMN}
COLUMNS: dict[str, dict[str, str]] = {
    "recipes": {
        "favorite": "BOOLEAN NOT NULL DEFAULT 0",
        "archived": "BOOLEAN NOT NULL DEFAULT 0",
        "by_heart": "BOOLEAN NOT NULL DEFAULT 0",
        "thumbs_up": "INTEGER NOT NULL DEFAULT 0",
        "thumbs_down": "INTEGER NOT NULL DEFAULT 0",
        "cooked_count": "INTEGER NOT NULL DEFAULT 0",
        "last_cooked": "VARCHAR(10)",
        "swapped_count": "INTEGER NOT NULL DEFAULT 0",
        "reviewed_on": "VARCHAR(10)",
        "collection": "VARCHAR(30) NOT NULL DEFAULT ''",
    },
    "plan_entries": {
        "kind": "VARCHAR(10) NOT NULL DEFAULT 'recipe'",
        "persons": "INTEGER",
        "text": "TEXT NOT NULL DEFAULT ''",
        "extras_json": "TEXT NOT NULL DEFAULT '[]'",
        "source_entry_id": "INTEGER",
        "cook_double": "VARCHAR(10)",
        "freezer_name": "VARCHAR(300)",
    },
    "freezer_items": {
        "source_entry_id": "INTEGER",
    },
    "basket_pushes": {
        "order_id": "VARCHAR(60)",
    },
}


def _existing_columns(conn, table: str) -> set[str] | None:
    if conn.dialect.name == "sqlite":
        rows = conn.execute(text(f'PRAGMA table_info("{table}")')).fetchall()
        return {r[1] for r in rows} if rows else None
    insp = inspect(conn)
    if not insp.has_table(table):
        return None
    return {c["name"] for c in insp.get_columns(table)}


def migrate(engine: Engine) -> list[str]:
    """Voeg ontbrekende kolommen toe. Geeft de toegevoegde kolommen terug ("tabel.kolom")."""
    added: list[str] = []
    with engine.begin() as conn:
        for table, columns in COLUMNS.items():
            existing = _existing_columns(conn, table)
            if existing is None:
                continue  # tabel bestaat (nog) niet: create_all maakt hem compleet
            for name, ddl in columns.items():
                if name not in existing:
                    conn.execute(text(f'ALTER TABLE "{table}" ADD COLUMN "{name}" {ddl}'))
                    added.append(f"{table}.{name}")
    if added:
        logger.info("Database gemigreerd: %s", ", ".join(added))
    return added
