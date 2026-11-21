# CLAUDE.md : application _APP_NAME_

Ce dépôt est une application de la plateforme `clemuscle-platform`. Elle est déployée par Flux à partir d'artefacts OCI publiés par la CI. Le fonctionnement de la plateforme est décrit dans le dépôt `infra` : `docs/architecture.md` et `CLAUDE.md`.

## Commandes (les mêmes partout)
- `make test` : lint, tests, garde-fou des migrations, validation de `deploy/` et scans. **Il doit passer avant toute PR.**
- `make run` : lance l'application en local sur le port 8080. `make build` construit l'image locale.
- `make modules` : applique `platform.yaml` à `deploy/`.
- `make logs TIER=staging|prod|preview PR=<n>` et `make status TIER=…` : lecture seule, avec `~/.kube/agent-reader.yaml`.
- `make deploy` est réservé à la CI. Ne le lance pas à la main.

## Comment livrer
1. Crée une branche, puis une PR vers `main`. Pose le label `preview` pour obtenir une préversion sur `https://_APP_NAME_-pr-<n>.<domaine>` (URL commentée par la CI).
2. Si tous les contrôles passent et qu'aucun contrôle `needs-human` ne reste en échec, la PR est **fusionnée automatiquement** et part en staging (`_APP_NAME_-staging.<domaine>`).
3. Production : pose une étiquette `vX.Y.Z` (semver) sur `main`. Tu peux le faire seul si **les objectifs de service du staging sont respectés depuis 24 h** (`deploy/base/slo.yaml`, alertes OpenObserve) et qu'aucun ticket `incident` n'est ouvert sur ce dépôt.
4. Retour arrière en production : une nouvelle étiquette `vX.Y.Z+1` depuis le dernier commit sain (`git revert` d'abord). Ne supprime jamais une étiquette publiée.

## Règles que la plateforme impose (sinon le déploiement est refusé)
- Images uniquement depuis `ghcr.io/clemuscle-platform/…` (et `docker.io/valkey/valkey`). En production, l'image est référencée par digest, ce que la CI fait toute seule.
- Conteneurs sans root, `readOnlyRootFilesystem`, `capabilities: drop: [ALL]`, `automountServiceAccountToken: false`.
- Chaque conteneur déclare `requests.cpu`, `requests.memory` et `limits.memory`. Les labels `app.kubernetes.io/name` et `platform.io/app` sont présents.
- Services `ClusterIP` uniquement. Les hôtes d'Ingress ont la forme `_APP_NAME_[-suffixe].<domaine>`.
- Pas de trafic vers les autres applications. La sortie vers Internet est fermée, sauf si elle est déclarée dans `infra/cluster/apps/_APP_NAME_.yaml` (champ `egress`, PR sur `infra` avec validation humaine).

## Modules
Les modules s'activent dans `platform.yaml`, puis avec `make modules` : `postgres`, `valkey`, `worker` (requiert valkey), `cron`, `s3` et `email`. Le type se choisit avec `kind: web | api | static`. **Ne modifie jamais à la main** les blocs `components` de `deploy/` : la CI le détecte.

## Interdits
- Écrire un secret en clair. Les secrets vont dans `deploy/overlays/<niveau>/secrets/*.sops.yaml` et se chiffrent avec `sops -e -i`. Ajoute ensuite le fichier aux `resources` de la surcouche. Tu ne disposes pas de la clé privée.
- Contourner `migration-guard`. Les migrations destructives (DROP, TRUNCATE, renommage, changement de type) suivent `docs/migrations.md` et attendent une validation humaine.
- Modifier une migration déjà fusionnée.
- Ajouter une dépendance sans figer sa version (`uv add pkg==x.y.z`). Renovate s'occupe des montées de version.
- Désactiver un contrôle de la CI, un scan, ou ajouter une exception `nosemgrep`, `.trivyignore` ou `gitleaks:allow` sans le justifier dans la PR et sans validation humaine.

## Diagnostic d'un incident (ticket `incident` ouvert par alert-bridge)
1. Lis le ticket : alerte, niveau, empreinte.
2. `make status TIER=prod`, `make logs TIER=prod`, puis le serveur MCP Flux (`get_flux_instance`, `get_kubernetes_resources`) en lecture seule.
3. Traces et journaux dans OpenObserve (flux `default`, filtre `service.name=_APP_NAME_`).
4. Corrige par une PR, ou reviens en arrière par une étiquette. Décris la cause dans le ticket, puis ferme-le quand l'alerte est résolue.
