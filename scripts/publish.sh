#!/usr/bin/env bash
# Construit et publie l'application pour la plateforme (ADR-0002). Utilisé par la CI et par « make deploy ».
#   1. image multi-architecture ghcr.io/<org>/<app>:<sha> (Dockerfile ou Dockerfile.static) ;
#   2. deploy/ avec l'image remplacée par son DIGEST ;
#   3. artefact OCI ghcr.io/<org>/<app>-deploy:<TAG> (Flux le déploie selon le tag) ;
#   4. signature cosign keyless de l'image et de l'artefact (CI uniquement : identité OIDC GitHub).
# Options : SCAN=true (trivy image avant l'artefact), SIGN=true (cosign), PLATFORMS, ALLOW_DIRTY=1.
# Tags d'artefact : pr-<n> (préversion), main (staging), X.Y.Z (production).
# Usage : TAG=main scripts/publish.sh     (prérequis : docker login ghcr.io, buildx, flux, kustomize)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out
: "${TAG:?TAG requis : pr-<n>, main ou X.Y.Z}"
ORG="${GITHUB_ORG:-clemuscle-platform}"
APP=$(sed -n 's/^name: *//p' platform.yaml)
KIND=$(sed -n 's/^kind: *//p' platform.yaml)
SHA=$(git rev-parse HEAD)
IMAGE="ghcr.io/$ORG/$APP"
DOCKERFILE=Dockerfile; [[ $KIND == static ]] && DOCKERFILE=Dockerfile.static
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
VERSION="$TAG"; [[ $TAG == main || $TAG == pr-* ]] && VERSION="$TAG-${SHA:0:7}"

if [[ -n "$(git status --porcelain)" && "${ALLOW_DIRTY:-}" != 1 ]]; then
  echo "arbre de travail modifié : commit d'abord (ou ALLOW_DIRTY=1)"; exit 1
fi

echo "== image $IMAGE:$SHA ($DOCKERFILE, $PLATFORMS)"
docker buildx build --platform "$PLATFORMS" -f "$DOCKERFILE" \
  --build-arg APP_VERSION="$VERSION" \
  --label org.opencontainers.image.revision="$SHA" \
  --provenance=mode=max --sbom=true \
  --metadata-file out/build-metadata.json \
  -t "$IMAGE:$SHA" --push .
DIGEST=$(jq -r '."containerimage.digest"' out/build-metadata.json)
echo "digest : $DIGEST"

# L'artefact (donc le déploiement) n'est publié que si l'image passe le scan.
if [[ "${SCAN:-false}" == true ]]; then
  echo "== trivy image (HIGH/CRITICAL corrigeables bloquants)"
  trivy image --quiet --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE@$DIGEST"
fi

echo "== artefact deploy/ → oci://$IMAGE-deploy:$TAG"
WORK=$(mktemp -d -p out)
cp -r deploy "$WORK/"
# La base renomme déjà « app-image » en $IMAGE:dev : c'est ce nom qu'il faut remplacer.
for o in "$WORK"/deploy/overlays/*/; do
  (cd "$o" && kustomize edit set image "$IMAGE=$IMAGE@$DIGEST")
  # Garde-fou : chaque niveau doit déployer l'image construite, par digest, et aucune autre.
  rendered=$(kustomize build "$o" | sed -n "s#^ *image: \($IMAGE[@:].*\)#\1#p" | sort -u)
  if [[ $rendered != "$IMAGE@$DIGEST" ]]; then
    echo "image non remplacée dans $(basename "$o") : ${rendered:-aucune}"; exit 1
  fi
done
flux push artifact "oci://$IMAGE-deploy:$TAG" \
  --path="$WORK/deploy" \
  --source="$(git config --get remote.origin.url || echo "https://github.com/$ORG/$APP")" \
  --revision="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}@sha1:$SHA" \
  --annotations="org.opencontainers.image.version=$VERSION" \
  --output=json > out/artifact.json
ARTIFACT_DIGEST=$(jq -r '.digest' out/artifact.json)
echo "artefact : $ARTIFACT_DIGEST"

if [[ "${SIGN:-false}" == true ]]; then
  echo "== signature cosign (keyless)"
  cosign sign --yes "$IMAGE@$DIGEST"
  cosign sign --yes "$IMAGE-deploy@$ARTIFACT_DIGEST"
fi
echo "publié : $IMAGE@$DIGEST, $IMAGE-deploy:$TAG"
