import importlib.util
import pathlib

import pytest

spec = importlib.util.spec_from_file_location(
    "migration_guard", pathlib.Path(__file__).parent.parent / "scripts" / "migration-guard.py"
)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


@pytest.mark.parametrize(
    "sql",
    [
        "DROP TABLE items;",
        "alter table items drop column name;",
        "ALTER TABLE items DROP name;",
        "TRUNCATE items;",
        "DELETE FROM items;",
        "ALTER TABLE items RENAME COLUMN name TO title;",
        "ALTER TABLE items ALTER COLUMN name TYPE varchar(10);",
    ],
)
def test_destructive_is_blocked(tmp_path, sql):
    f = tmp_path / "0002.sql"
    f.write_text(sql)
    assert guard.check(f)


@pytest.mark.parametrize(
    "sql",
    [
        "CREATE TABLE t (id int);",
        "ALTER TABLE items ADD COLUMN note text;",
        "ALTER TABLE items ALTER COLUMN name DROP DEFAULT;",
        "ALTER TABLE items ALTER COLUMN name DROP NOT NULL;",
        "DELETE FROM items WHERE created_at < now() - interval '1 year';",
        "-- DROP TABLE items;\nCREATE INDEX i ON items (name);",
    ],
)
def test_safe_is_allowed(tmp_path, sql):
    f = tmp_path / "0002.sql"
    f.write_text(sql)
    assert guard.check(f) == []


def test_repo_migrations_are_safe():
    for f in sorted((pathlib.Path(__file__).parent.parent / "migrations").glob("*.sql")):
        assert guard.check(f) == [], f
