"""Module s3 : stockage d'objets (Garage en local, Hetzner Object Storage en production).

Chaque application écrit sous son préfixe (S3_PREFIX = namespace), dans le bucket partagé S3_BUCKET.
"""

import json
import re
from functools import cache

from app.config import settings

_SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]{1,200}$")


@cache
def client():
    import boto3

    return boto3.client("s3", endpoint_url=settings.s3_endpoint)


def put_json(name: str, body: dict) -> dict:
    if not _SAFE_NAME.match(name):
        raise ValueError("nom de fichier invalide")
    key = f"{settings.s3_prefix}/{name}.json" if settings.s3_prefix else f"{name}.json"
    client().put_object(
        Bucket=settings.s3_bucket, Key=key, Body=json.dumps(body).encode(), ContentType="application/json"
    )
    return {"bucket": settings.s3_bucket, "key": key}
