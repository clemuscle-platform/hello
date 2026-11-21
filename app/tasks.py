"""Module cron : tâches planifiées, lancées par le CronJob.

python -m app.tasks cleanup
"""

import logging
import sys

from app import db
from app.config import settings

log = logging.getLogger(f"{settings.app_name}.tasks")


def cleanup() -> int:
    if not settings.modules["postgres"]:
        log.info("rien à nettoyer (module postgres non activé)")
        return 0
    with db.connect() as conn:
        deleted = conn.execute("DELETE FROM items WHERE created_at < now() - interval '90 days'").rowcount
    log.info("nettoyage : %s élément(s) supprimé(s)", deleted)
    return 0


TASKS = {"cleanup": cleanup}


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
    if len(argv) != 1 or argv[0] not in TASKS:
        print(f"usage : python -m app.tasks {{{','.join(TASKS)}}}", file=sys.stderr)
        return 2
    return TASKS[argv[0]]()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
