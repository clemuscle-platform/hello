"""Application d'exemple : pages web, API JSON, sondes de santé, modules optionnels.

Lancement en production (Dockerfile) :
    opentelemetry-instrument uvicorn app.main:app --host 0.0.0.0 --port 8080
L'instrumentation OTel (traces, métriques, journaux) est configurée par les variables OTEL_*.
"""

import html
import logging

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app import cache, db, storage
from app.config import settings
from app.errors import init_error_tracking

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
log = logging.getLogger(settings.app_name)
init_error_tracking()

app = FastAPI(title=settings.app_name, version=settings.version, docs_url="/api/docs", redoc_url=None)


@app.get("/healthz", include_in_schema=False)
def healthz() -> dict:
    """Vivacité : le processus répond."""
    return {"status": "ok"}


@app.get("/readyz", include_in_schema=False)
def readyz() -> dict:
    """Disponibilité : les dépendances activées répondent."""
    checks = {}
    if settings.modules["postgres"]:
        checks["postgres"] = db.ping()
    if settings.modules["valkey"]:
        checks["valkey"] = cache.ping()
    if not all(checks.values()):
        raise HTTPException(status_code=503, detail=checks)
    return {"status": "ready", "checks": checks}


@app.get("/api/info")
def info() -> dict:
    return {
        "app": settings.app_name,
        "version": settings.version,
        "tier": settings.tier,
        "modules": settings.modules,
    }


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)


@app.get("/api/items")
def list_items() -> list[dict]:
    if not settings.modules["postgres"]:
        raise HTTPException(status_code=501, detail="module postgres non activé")
    return db.list_items()


@app.post("/api/items", status_code=201)
def create_item(item: ItemIn) -> dict:
    if not settings.modules["postgres"]:
        raise HTTPException(status_code=501, detail="module postgres non activé")
    created = db.create_item(item.name)
    if settings.modules["valkey"]:
        cache.enqueue("items", str(created["id"]))
    return created


@app.post("/api/files/{name}", status_code=201)
def put_file(name: str, body: dict) -> dict:
    if not settings.modules["s3"]:
        raise HTTPException(status_code=501, detail="module s3 non activé")
    return storage.put_json(name, body)


if settings.app_kind == "web":

    @app.get("/", response_class=HTMLResponse, include_in_schema=False)
    def index() -> str:
        modules = ", ".join(k for k, v in settings.modules.items() if v) or "aucun"
        return (
            "<!doctype html><html lang='fr'><meta charset='utf-8'>"
            f"<title>{html.escape(settings.app_name)}</title>"
            f"<h1>{html.escape(settings.app_name)}</h1>"
            f"<p>Version {html.escape(settings.version)} — niveau {html.escape(settings.tier)}</p>"
            f"<p>Modules actifs : {html.escape(modules)}</p></html>"
        )
