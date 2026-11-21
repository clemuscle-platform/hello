"""Applique les migrations SQL de migrations/ dans l'ordre, une seule fois chacune.

Lancé par le Job « migrate » avant le déploiement (module postgres) :
    python -m app.migrate
Règle expand/contract : une migration ne supprime jamais de table ni de colonne dans la même
version que le code qui cesse de l'utiliser. Les opérations destructives sont bloquées par la CI
(scripts/migration-guard.py) tant qu'un humain ne les a pas approuvées.
"""

import hashlib
import pathlib
import sys

from app import db

MIGRATIONS = pathlib.Path(__file__).resolve().parent.parent / "migrations"


def main() -> int:
    files = sorted(MIGRATIONS.glob("*.sql"))
    with db.connect() as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            " name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())"
        )
        # Verrou applicatif : deux Jobs simultanés ne migrent pas en parallèle.
        conn.execute("SELECT pg_advisory_xact_lock(424242)")
        done = dict(conn.execute("SELECT name, checksum FROM schema_migrations").fetchall())
        for f in files:
            sql = f.read_text()
            checksum = hashlib.sha256(sql.encode()).hexdigest()
            if f.name in done:
                if done[f.name] != checksum:
                    print(f"ERREUR : {f.name} a été modifiée après application", file=sys.stderr)
                    return 1
                continue
            print(f"migration {f.name}")
            conn.execute(sql)
            conn.execute("INSERT INTO schema_migrations (name, checksum) VALUES (%s, %s)", (f.name, checksum))
    print("migrations à jour")
    return 0


if __name__ == "__main__":
    sys.exit(main())
