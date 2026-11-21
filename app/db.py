"""Module postgres : accès à la base CloudNativePG (DATABASE_URL = clé « uri » du Secret <app>-pg-app)."""

from contextlib import contextmanager

from app.config import settings


@contextmanager
def connect():
    import psycopg

    with psycopg.connect(settings.database_url, connect_timeout=3) as conn:
        yield conn


def ping() -> bool:
    try:
        with connect() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        return False


def list_items() -> list[dict]:
    with connect() as conn:
        rows = conn.execute("SELECT id, name, created_at FROM items ORDER BY id DESC LIMIT 100").fetchall()
    return [{"id": r[0], "name": r[1], "created_at": r[2].isoformat()} for r in rows]


def create_item(name: str) -> dict:
    with connect() as conn:
        row = conn.execute("INSERT INTO items (name) VALUES (%s) RETURNING id, name, created_at", (name,)).fetchone()
    return {"id": row[0], "name": row[1], "created_at": row[2].isoformat()}
