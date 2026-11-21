"""Module valkey : cache et file de messages simple (VALKEY_URL)."""

from functools import cache as _memo

from app.config import settings


@_memo
def client():
    import redis

    return redis.Redis.from_url(settings.valkey_url, socket_timeout=3, decode_responses=True)


def ping() -> bool:
    try:
        return bool(client().ping())
    except Exception:
        return False


def enqueue(queue: str, payload: str) -> None:
    client().lpush(f"{settings.app_name}:{queue}", payload)


def dequeue(queue: str, timeout: int = 5) -> str | None:
    item = client().brpop([f"{settings.app_name}:{queue}"], timeout=timeout)
    return item[1] if item else None
