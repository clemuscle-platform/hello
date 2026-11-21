#!/usr/bin/env python3
"""Garde-fou des migrations SQL (règles d'autonomie, ADR-0009 et ADR-0014).

Échoue (code 1) si une migration ajoutée ou modifiée par rapport à la branche de base contient une
opération destructive. La CI pose alors le contrôle requis « migration-guard » en échec : seule
l'approbation d'un membre de platform-admins (environnement GitHub « destructive-migration ») le lève.

Usage : migration-guard.py [--base origin/main] [fichiers...]
Sans fichiers : compare migrations/*.sql avec la branche de base (git diff).
"""

import argparse
import pathlib
import re
import subprocess
import sys

DESTRUCTIVE = [
    (r"\bDROP\s+(TABLE|SCHEMA|DATABASE|VIEW|MATERIALIZED\s+VIEW|TYPE|INDEX)\b", "DROP d'un objet"),
    (r"\bALTER\s+TABLE\b[^;]*\bDROP\s+(COLUMN\b|CONSTRAINT\b|(?!DEFAULT|NOT\s+NULL)\w)", "suppression de colonne"),
    (r"\bTRUNCATE\b", "TRUNCATE"),
    (r"\bDELETE\s+FROM\b(?![^;]*\bWHERE\b)", "DELETE sans WHERE"),
    (r"\bALTER\s+TABLE\b[^;]*\bRENAME\b", "renommage (casse le code déployé)"),
    (r"\bALTER\s+TABLE\b[^;]*\bALTER\s+(COLUMN\s+)?\w+\s+(SET\s+DATA\s+)?TYPE\b", "changement de type de colonne"),
]


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    return re.sub(r"--[^\n]*", " ", sql)


def changed_files(base: str) -> list[pathlib.Path]:
    out = subprocess.run(  # noqa: S603
        ["git", "diff", "--name-only", "--diff-filter=AM", f"{base}...HEAD", "--", "migrations/"],  # noqa: S607
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [pathlib.Path(p) for p in out.split() if p.endswith(".sql")]


def check(path: pathlib.Path) -> list[str]:
    sql = strip_comments(path.read_text())
    return [f"{path}: {label}" for pattern, label in DESTRUCTIVE if re.search(pattern, sql, re.I)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("files", nargs="*", type=pathlib.Path)
    args = ap.parse_args()
    files = args.files or changed_files(args.base)
    problems = [p for f in files for p in check(f)]
    if problems:
        print("Migration destructive détectée : validation humaine requise.\n  " + "\n  ".join(problems))
        print("Procédure expand/contract : docs/migrations.md")
        return 1
    print(f"migration-guard : {len(files)} fichier(s) vérifié(s), rien de destructif")
    return 0


if __name__ == "__main__":
    sys.exit(main())
