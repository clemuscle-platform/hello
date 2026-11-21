#!/usr/bin/env python3
"""Synchronise les composants Kustomize de deploy/ avec platform.yaml.

scripts/modules.py           écrit les listes « components » (base et surcouches)
scripts/modules.py --check   échoue si deploy/ ne correspond pas à platform.yaml (CI)
"""

import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Ordre canonique : les composants qui CRÉENT des charges passent avant ceux qui les PATCHENT.
ORDER = ["worker", "cron", "valkey", "postgres", "s3", "email"]
REQUIRES = {"worker": ["valkey"]}
KINDS = {"web": [], "api": ["api"], "static": ["static"]}
BLOCK = re.compile(r"# BEGIN modules.*?# END modules", re.S)


def wanted(cfg: dict) -> dict[str, list[str]]:
    mods = {m for m, on in (cfg.get("modules") or {}).items() if on}
    unknown = mods - set(ORDER)
    if unknown:
        sys.exit(f"modules inconnus : {sorted(unknown)}")
    for m, deps in REQUIRES.items():
        if m in mods and not set(deps) <= mods:
            sys.exit(f"le module {m} requiert : {deps}")
    kind = cfg.get("kind", "web")
    if kind not in KINDS:
        sys.exit(f"kind inconnu : {kind} (web, api, static)")
    if kind == "static" and mods:
        sys.exit("un site statique n'accepte aucun module")
    base = [f"../components/{c}" for c in KINDS[kind] + [m for m in ORDER if m in mods]]
    backup = ["../../components/postgres-backup"] if "postgres" in mods else []
    return {
        "deploy/base/kustomization.yaml": base,
        "deploy/overlays/preview/kustomization.yaml": [],
        "deploy/overlays/staging/kustomization.yaml": backup,
        "deploy/overlays/prod/kustomization.yaml": backup,
    }


def render(components: list[str]) -> str:
    body = "components: []" if not components else "components:\n" + "\n".join(f"  - {c}" for c in components)
    return f"# BEGIN modules (géré par scripts/modules.py)\n{body}\n# END modules"


def main() -> int:
    check = "--check" in sys.argv
    cfg = yaml.safe_load((ROOT / "platform.yaml").read_text())
    drift = []
    for rel, comps in wanted(cfg).items():
        path = ROOT / rel
        text = path.read_text()
        if not BLOCK.search(text):
            sys.exit(f"bloc « BEGIN/END modules » absent de {rel}")
        new = BLOCK.sub(render(comps), text)
        if new != text:
            drift.append(rel)
            if not check:
                path.write_text(new)
    if check and drift:
        print("deploy/ ne correspond pas à platform.yaml (lancer « make modules ») :\n  " + "\n  ".join(drift))
        return 1
    print("modules : " + ("à jour" if not drift else f"{len(drift)} fichier(s) mis à jour"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
