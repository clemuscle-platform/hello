"""Suivi d'erreurs (Sentry ou GlitchTip, compatibles) : actif seulement si SENTRY_DSN est défini."""

from app.config import settings


def init_error_tracking() -> None:
    if not settings.sentry_dsn:
        return
    import sentry_sdk

    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.tier,
        release=settings.version,
        send_default_pii=False,  # pas de données personnelles (IP, cookies, en-têtes)
        traces_sample_rate=0.0,  # les traces passent par OpenTelemetry
    )
