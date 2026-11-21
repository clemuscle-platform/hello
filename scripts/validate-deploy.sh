#!/usr/bin/env bash
# Valide deploy/ hors cluster, comme le ferait la plateforme :
#   kustomize build de chaque niveau → substitution des variables (valeurs d'exemple) → kubeconform
#   → règles d'admission de la plateforme (CLI kyverno, si INFRA_DIR pointe vers le dépôt infra).
# Trois configurations sont testées : platform.yaml du dépôt, tous les modules, site statique.
# Usage : scripts/validate-deploy.sh   (INFRA_DIR=../infra par défaut)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
INFRA_DIR="${INFRA_DIR:-$ROOT/../infra}"
OUT="$ROOT/out/deploy"
mkdir -p "$OUT"
K8S_VERSION="${K8S_VERSION:-1.35.0}"
APP=$(uv run --frozen python -c "import yaml;print(yaml.safe_load(open('platform.yaml'))['name'])")
fail=0

uv run --frozen python scripts/modules.py --check || fail=1

variant() { # variant <nom> <python qui modifie cfg>
  local name=$1 code=$2 dir
  dir=$(mktemp -d -p "$OUT")
  cp -r deploy platform.yaml scripts "$dir/"
  python3 -I - "$dir/platform.yaml" "$code" <<'PY'
import sys, yaml
path, code = sys.argv[1], sys.argv[2]
cfg = yaml.safe_load(open(path))
exec(code)
yaml.safe_dump(cfg, open(path, "w"))
PY
  uv run --frozen --project "$ROOT" python "$dir/scripts/modules.py" >/dev/null
  echo "$dir"
}

declare -A VARIANTS=(
  [repo]="pass"
  [all-modules]="cfg['kind']='web'; cfg['modules']={m: True for m in cfg['modules']}"
  [static]="cfg['kind']='static'; cfg['modules']={m: False for m in cfg['modules']}"
)

for v in "${!VARIANTS[@]}"; do
  dir=$(variant "$v" "${VARIANTS[$v]}")
  for tier in preview staging prod; do
    ns="app-$APP-$tier"; host="$APP-$tier.localhost"
    [[ $tier == preview ]] && { ns="app-$APP-pr-1"; host="$APP-pr-1.localhost"; }
    [[ $tier == prod ]] && host="$APP.localhost"
    out="$OUT/$v-$tier.yaml"
    if ! kustomize build "$dir/deploy/overlays/$tier" > "$out.raw"; then
      echo "ÉCHEC kustomize build ($v/$tier)"; fail=1; continue
    fi
    APP_NAME=$APP APP_TIER=$tier APP_NAMESPACE=$ns APP_HOST=$host CLUSTER_ENV=local \
    CLUSTER_DOMAIN=localhost CLUSTER_ISSUER=selfsigned-ca STORAGE_CLASS=local-path \
    S3_ENDPOINT=http://garage.platform-s3.svc.cluster.local:3900 S3_REGION=garage \
    S3_BUCKET_PG=platform-pg S3_BUCKET_APPS=platform-apps \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.platform-otel.svc:4318 \
      flux envsubst --strict < "$out.raw" > "$out" || { echo "ÉCHEC substitution ($v/$tier)"; fail=1; continue; }
    # Pour les règles d'admission, on simule l'image par digest posée par la CI.
    sed -i -E "s#(image: )app-image#\1ghcr.io/clemuscle-platform/$APP@sha256:$(printf '0%.0s' {1..64})#; s#(image: ghcr.io/clemuscle-platform/$APP):dev#\1@sha256:$(printf '0%.0s' {1..64})#" "$out"
    echo "$ns" > "$out.ns"
    echo "ok  $v/$tier ($(grep -c '^kind:' "$out") objets)"
  done
done

echo "== kubeconform"
KC_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/kubeconform"
mkdir -p "$KC_CACHE"  # absent sur un runner neuf : kubeconform échoue sinon
kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" -cache "$KC_CACHE" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -skip ServiceLevelObjectives \
  "$OUT"/*-preview.yaml "$OUT"/*-staging.yaml "$OUT"/*-prod.yaml || fail=1

if [[ -f "$INFRA_DIR/cluster/base/policies/app-policies.yaml" ]]; then
  echo "== règles d'admission de la plateforme ($INFRA_DIR)"
  GITHUB_ORG=clemuscle-platform CLUSTER_DOMAIN=localhost \
    flux envsubst --strict < "$INFRA_DIR/cluster/base/policies/app-policies.yaml" > "$OUT/policies.yaml"
  for f in "$OUT"/*-preview.yaml "$OUT"/*-staging.yaml "$OUT"/*-prod.yaml; do
    tier=$(basename "$f" .yaml); tier=${tier##*-}
    ns=$(cat "$f.ns")
    cat > "$OUT/values.yaml" <<EOF
apiVersion: cli.kyverno.io/v1alpha1
kind: Value
metadata: {name: ns}
namespaceSelector:
  - name: $ns
    labels: {platform.io/managed: "true", platform.io/app: $APP, platform.io/tier: $tier}
EOF
    cat > "$OUT/user.yaml" <<EOF
apiVersion: cli.kyverno.io/v1alpha1
kind: UserInfo
metadata: {name: tenant}
userInfo: {username: "system:serviceaccount:flux-system:$ns"}
EOF
    # Les CRD (CNPG…) ne sont pas résolues hors cluster par la CLI kyverno : on les exclut ici.
    uv run --frozen python - "$f" "$ns" <<'PY2'
import sys, yaml
src, ns = sys.argv[1], sys.argv[2]
core = ("v1", "apps/v1", "batch/v1", "networking.k8s.io/v1", "policy/v1")
docs = []
for d in yaml.safe_load_all(open(src)):
    if d and d["apiVersion"] in core:
        d["metadata"]["namespace"] = ns  # posé par Flux (targetNamespace) dans le cluster
        docs.append(d)
yaml.safe_dump_all(docs, open(src + ".core", "w"))
PY2
    res=$(kyverno apply "$OUT/policies.yaml" --resource "$f.core" --userinfo "$OUT/user.yaml" --values-file "$OUT/values.yaml" 2>&1 | tail -1)
    if [[ $res != *"fail: 0"* || $res != *"error: 0"* ]]; then
      echo "ÉCHEC règles d'admission $(basename "$f") : $res"
      kyverno apply "$OUT/policies.yaml" --resource "$f.core" --userinfo "$OUT/user.yaml" --values-file "$OUT/values.yaml" --output-format table 2>&1 | grep -E 'Fail|Error' | head
      fail=1
    else
      echo "ok  $(basename "$f") : $res"
    fi
  done
else
  echo "(règles d'admission ignorées : INFRA_DIR=$INFRA_DIR introuvable)"
fi

(( fail )) && { echo "ÉCHEC de la validation de deploy/"; exit 1; }
echo "Validation deploy/ : OK"
