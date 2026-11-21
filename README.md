# _APP_NAME_

Application de la plateforme `clemuscle-platform`, créée depuis le modèle **app-template**.

## Démarrer une nouvelle application
1. Sur GitHub : *Use this template*, puis créer le dépôt `clemuscle-platform/<nom>` (privé).
2. Initialiser le dépôt : `scripts/init.sh <nom> web|api|static`, puis `make setup test` et un commit.
3. Activer les modules voulus dans `platform.yaml`, puis lancer `make modules`.
4. Déclarer l'application dans le dépôt `infra` : copier `cluster/apps/hello.yaml` en `cluster/apps/<nom>.yaml` et l'ajouter à `cluster/apps/kustomization.yaml`. Cette PR demande une validation humaine (runbook *ajout d'une application*).
5. Pousser sur `main` : la CI publie l'artefact `main`, et Flux déploie le staging.

## Arborescence

| Chemin | Rôle |
|---|---|
| `app/` | Application FastAPI : web, API, santé (`/healthz`, `/readyz`), modules |
| `migrations/` | SQL appliqué par `python -m app.migrate` (initContainer) |
| `static/` | Site statique (`kind: static`, `Dockerfile.static`) |
| `deploy/base/` | Deployment, Service, Ingress, ServiceAccount, configuration OTel, objectifs de service |
| `deploy/components/` | Modules Kustomize : api, static, worker, cron, valkey, postgres, postgres-backup, s3, email |
| `deploy/overlays/{preview,staging,prod}/` | Niveaux de déploiement |
| `platform.yaml` | Type et modules activés (source de vérité) |
| `scripts/` | `publish.sh` (CI), `modules.py`, `migration-guard.py`, `validate-deploy.sh`, `init.sh` |

## Variables fournies par la plateforme
`APP_NAME`, `APP_TIER`, `APP_NAMESPACE`, `APP_HOST`, `CLUSTER_DOMAIN`, `CLUSTER_ISSUER`, `STORAGE_CLASS`, `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET_PG`, `S3_BUCKET_APPS` et `OTEL_EXPORTER_OTLP_ENDPOINT` : la Kustomization Flux les substitue dans `deploy/`.

## Observabilité
L'image démarre avec `opentelemetry-instrument`. Les traces (FastAPI, psycopg, redis, botocore), les métriques et les journaux sont envoyés en OTLP au collecteur de la plateforme. Celui-ci masque les secrets et les données personnelles avant le stockage dans OpenObserve. Le suivi d'erreurs (Sentry ou GlitchTip) s'active avec `SENTRY_DSN`, dans `deploy/overlays/<niveau>/secrets/app-secrets.sops.yaml`.
