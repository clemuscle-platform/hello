# Migrations de base de données

Les migrations sont des fichiers SQL dans `migrations/`, appliqués dans l'ordre par `python -m app.migrate`. Elles tournent dans l'initContainer `migrate`, avant le démarrage de chaque nouvelle version.

## Règles

1. **Un fichier appliqué n'est jamais modifié.** `app.migrate` compare les sommes de contrôle et refuse de continuer si un fichier a changé.
2. **Expand/contract** : on ne supprime ni ne renomme rien dans la version qui cesse de l'utiliser.
   - Version N (expand) : ajouter la nouvelle colonne, écrire dans les deux, lire la nouvelle.
   - Version N+1 : le code n'utilise plus l'ancienne colonne.
   - Version N+2 (contract) : supprimer l'ancienne colonne. **C'est une migration destructive, qui exige une validation humaine.**
3. **Migrations destructives** (`DROP TABLE` ou `DROP COLUMN`, `TRUNCATE`, `DELETE` sans `WHERE`, renommage, changement de type) : le contrôle `migration-guard` de la CI échoue. La PR ne peut être fusionnée qu'après l'approbation d'un membre de `platform-admins`, dans l'environnement GitHub `destructive-migration`. Un agent ne contourne jamais ce contrôle.
4. Avant une migration destructive en production, il faut vérifier qu'une sauvegarde récente existe (`kubectl get backups -n app-<app>-prod`) et noter dans la PR comment revenir en arrière (restauration PITR, voir le runbook *restauration d'une base* du dépôt infra).

## Exemple : renommer `name` en `title`

| PR | Migration | Code |
|---|---|---|
| 1 | `ALTER TABLE items ADD COLUMN title text;` puis `UPDATE items SET title = name;` | écrit dans `name` et dans `title`, lit `title` |
| 2 | — | n'utilise plus `name` |
| 3 (humain) | `ALTER TABLE items DROP COLUMN name;` | — |
