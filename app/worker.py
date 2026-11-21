"""Module worker : traite la file « items » (module valkey requis).

python -m app.worker
"""

import logging
import signal
import sys

from app import cache
from app.config import settings

log = logging.getLogger(f"{settings.app_name}.worker")
_running = True


def _stop(*_):
    global _running
    _running = False


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    if not settings.modules["valkey"]:
        log.error("VALKEY_URL non défini : le worker a besoin du module valkey")
        return 1
    signal.signal(signal.SIGTERM, _stop)
    log.info("worker démarré")
    while _running:
        item = cache.dequeue("items", timeout=5)
        if item:
            log.info("traitement de l'élément %s", item)
    log.info("worker arrêté proprement")
    return 0


if __name__ == "__main__":
    sys.exit(main())
