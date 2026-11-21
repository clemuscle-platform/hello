# syntax=docker/dockerfile:1.7
# Image de l'application (types web et api). Multi-architecture (amd64, arm64) via buildx dans la CI.
# Non root, système de fichiers en lecture seule possible, aucun outil de build dans l'image finale.
# Les digests des images de base sont épinglés par Renovate (pinDigests).

FROM ghcr.io/astral-sh/uv:0.13.8 AS uv

FROM python:3.14.10-slim-trixie AS build
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
COPY app ./app
COPY migrations ./migrations

FROM python:3.14.10-slim-trixie
ARG APP_VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/clemuscle-platform/hello" \
      org.opencontainers.image.version="${APP_VERSION}"
# Correctifs de sécurité de l'OS de base, puis retrait de pip/setuptools (inutiles à l'exécution,
# et porteurs de dépendances vendorisées vulnérables). L'application tourne dans /app/.venv.
RUN apt-get update \
 && apt-get -y upgrade --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && (python -m pip uninstall -y -q pip setuptools 2>/dev/null || true) \
 && rm -rf /usr/local/lib/python3.14/site-packages/pip* /usr/local/lib/python3.14/site-packages/setuptools* \
 && useradd --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=build --chown=root:root /app /app
ENV PATH=/app/.venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_VERSION=${APP_VERSION}
USER 10001:10001
EXPOSE 8080
HEALTHCHECK NONE
CMD ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-server-header", "--proxy-headers", "--forwarded-allow-ips", "*"]
