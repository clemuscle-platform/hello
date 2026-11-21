#!/usr/bin/env bash
# Initialise un nouveau dépôt créé depuis app-template : renomme « hello » en <nom> partout.
# Usage : scripts/init.sh <nom> [web|api|static]
# Le nom sert de préfixe aux namespaces (app-<nom>-prod…) et aux hôtes : [a-z][a-z0-9-]{1,19}.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="${1:?usage: scripts/init.sh <nom> [web|api|static]}"
KIND="${2:-web}"
[[ $NAME =~ ^[a-z][a-z0-9-]{1,19}$ ]] || { echo "nom invalide : $NAME"; exit 1; }
[[ $KIND =~ ^(web|api|static)$ ]] || { echo "type invalide : $KIND"; exit 1; }
[[ $(sed -n 's/^name: *//p' platform.yaml) == hello ]] || { echo "dépôt déjà initialisé"; exit 1; }

sed -i "s/^name: hello$/name: $NAME/; s/^kind: .*/kind: $KIND/" platform.yaml
sed -i "s/^name = \"hello\"$/name = \"$NAME\"/" pyproject.toml
sed -i "s#ghcr.io/clemuscle-platform/hello#ghcr.io/clemuscle-platform/$NAME#" deploy/base/kustomization.yaml
sed -i "s#github.com/clemuscle-platform/hello#github.com/clemuscle-platform/$NAME#" Dockerfile
sed -i "s/_APP_NAME_/$NAME/g" CLAUDE.md README.md
uv lock -q
uv run --frozen python scripts/modules.py
echo "Initialisé : $NAME ($KIND)."
echo "Étape suivante : déclarer l'application dans le dépôt infra (cluster/apps/$NAME.yaml), voir README."
