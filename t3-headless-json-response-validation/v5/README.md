# TYPO3 Headless — Stratégie de validation JSON

Tests PHPUnit pour valider les endpoints JSON d'un projet TYPO3 v13 headless.

## Source de vérité : `tests/database/typo3_test.sql.gz`

Le dump SQL de la base EC2 de référence est versionné dans Git.
Tous les développeurs et le CI l'utilisent comme base de test commune.

## Démarrage rapide

```bash
git clone <repo> && composer install
chmod +x setup-git-hooks.sh Tests/Scripts/*.sh
./setup-git-hooks.sh

# Importer la base de référence
./Tests/Scripts/import_dump.sh

# Générer les snapshots locaux
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# Lancer les tests
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless --testdox
```

## Workflows

| Situation | Référence |
|---|---|
| Nouveau plugin | [Partie 1](./TYPO3-HEADLESS-VALIDATION.md#partie-1--développement-initial-dun-nouveau-plugin) |
| Modifier un plugin existant | [Partie 2](./TYPO3-HEADLESS-VALIDATION.md#partie-2--modification-dun-plugin-existant) |
| Cleanup mensuel EC2 | [Partie 3](./TYPO3-HEADLESS-VALIDATION.md#partie-3--cleanup-mensuel-de-la-base-de-test-sur-ec2) |
| Nouveau développeur | [Partie 4](./TYPO3-HEADLESS-VALIDATION.md#partie-4--arrivée-dun-nouveau-développeur) |

## Règle principale

Les tests **peuvent échouer en CI sur une MR** si la feature nécessite des données pas encore dans la base stable. C'est attendu — documenter les données requises dans la MR, les ajouter sur l'EC2 après merge.

→ [Documentation complète](./TYPO3-HEADLESS-VALIDATION.md)
