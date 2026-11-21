"""Configuration lue dans l'environnement (12-factor). Aucun secret n'a de valeur par défaut."""

import os
from dataclasses import dataclass, field


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


@dataclass(frozen=True)
class Settings:
    app_name: str = field(default_factory=lambda: _env("APP_NAME", "hello"))
    # web : pages HTML + API ; api : API JSON uniquement
    app_kind: str = field(default_factory=lambda: _env("APP_KIND", "web"))
    tier: str = field(default_factory=lambda: _env("APP_TIER", "dev"))
    version: str = field(default_factory=lambda: _env("APP_VERSION", "dev"))
    database_url: str = field(default_factory=lambda: _env("DATABASE_URL"))
    valkey_url: str = field(default_factory=lambda: _env("VALKEY_URL"))
    s3_endpoint: str = field(default_factory=lambda: _env("S3_ENDPOINT"))
    s3_bucket: str = field(default_factory=lambda: _env("S3_BUCKET"))
    s3_prefix: str = field(default_factory=lambda: _env("S3_PREFIX"))
    smtp_host: str = field(default_factory=lambda: _env("SMTP_HOST"))
    sentry_dsn: str = field(default_factory=lambda: _env("SENTRY_DSN"))

    @property
    def modules(self) -> dict[str, bool]:
        return {
            "postgres": bool(self.database_url),
            "valkey": bool(self.valkey_url),
            "s3": bool(self.s3_endpoint and self.s3_bucket),
            "email": bool(self.smtp_host),
            "sentry": bool(self.sentry_dsn),
        }


settings = Settings()
