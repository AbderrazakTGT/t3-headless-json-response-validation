# Base de données de référence pour les tests

## Principe

Ce dossier contient le **dump SQL de référence** utilisé par tous les développeurs
et par le CI. C'est la source de vérité pour les tests headless.

```
tests/database/
├── typo3_test.sql.gz     → dump compressé de la base EC2 de référence
└── README.md             → ce fichier
```

## Origine du dump

Le dump provient de l'instance **EC2 de test** après chaque cleanup mensuel
ou après l'ajout de données pour une nouvelle feature.

**Processus de mise à jour :**

```
merge sur main
  → développeur se connecte à l'EC2
  → ajoute les données nécessaires via le backend TYPO3
  → lance le cleanup (cleanup_ec2.sh)
  → exporte le dump (export_dump.sh)
  → commit : git add tests/database/typo3_test.sql.gz
  → push sur main
```

## Utilisation

### Développeur (après git clone ou git pull)

```bash
# Importer la base de référence dans DDEV
./Tests/Scripts/import_dump.sh

# Générer les snapshots locaux à partir de cette base
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# Lancer les tests
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless --testdox
```

### CI

Le CI importe ce dump directement dans sa base MySQL de test.
Voir `.gitlab-ci.yml` stage `prepare:import-dump`.

## Ce que contient ce dump

- Pages de référence couvrant les 5 scénarios de test
- Contenus texte, images, catégories
- FE users de test (standard, premium, admin) avec données anonymisées
- FE groups correspondants
- Aucune donnée de production, aucune donnée réelle RGPD

## Règles

- Ce dump est **anonymisé** : aucune donnée personnelle réelle
- Il est **stable** : ne change qu'après un merge sur main
- Il est **partagé** : tous les devs et le CI utilisent le même dump
- Les tests qui échouent en CI sur une MR indiquent que la base
  doit être mise à jour après le merge (comportement attendu)
