from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_healthz():
    assert client.get("/healthz").json() == {"status": "ok"}


def test_readyz_without_modules():
    r = client.get("/readyz")
    assert r.status_code == 200
    assert r.json()["checks"] == {}


def test_info_lists_modules():
    body = client.get("/api/info").json()
    assert body["app"]
    assert set(body["modules"]) == {"postgres", "valkey", "s3", "email", "sentry"}


def test_items_require_postgres_module():
    assert client.get("/api/items").status_code == 501


def test_index_escapes_html():
    r = client.get("/")
    assert r.status_code == 200
    assert "<script" not in r.text.lower()
