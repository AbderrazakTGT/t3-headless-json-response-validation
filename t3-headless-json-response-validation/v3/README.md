# TYPO3 Headless — Stratégie de validation JSON

Tests PHPUnit pour valider les endpoints JSON d'un projet TYPO3 v13 headless.

## Démarrage rapide

```bash
# 1. Dépendances
composer require --dev typo3/testing-framework:"^8.0" justinrainbow/json-schema

# 2. Hooks Git (une seule fois)
chmod +x setup-git-hooks.sh && ./setup-git-hooks.sh

# 3. Générer les snapshots locaux
chmod +x Tests/Scripts/*.sh
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# 4. Lancer les tests
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless --testdox
```

> Les fixtures CSV sont dans Git (anonymisées). Les snapshots sont gitignorés (générés localement).
> Fonctionne **hors-ligne** (TGV, avion) — aucune connexion réseau requise après `git clone`.

## Scénarios de test

| Scénario | UID | Cas testé |
|---|---|---|
| `page_simple` | 1 | Page publique basique |
| `page_with_content` | 2 | Contenu texte multi-éléments |
| `page_with_images` | 3 | Images FAL (sys_file) |
| `page_with_categories` | 4 | Catégories TYPO3 |
| `page_protected` | 5 | Page protégée (FE user requis) |

## FE users de test

| UID | Username | Rôle | Mot de passe |
|---|---|---|---|
| 100 | `test_standard` | Groupe 1 | `password` |
| 101 | `test_premium` | Groupes 1+2 | `password` |
| 102 | `test_admin` | Groupes 1+2+3 | `password` |

## Mise à jour des fixtures (après extraction d'une nouvelle base)

```bash
# Nettoyer les soft-deletes TYPO3 (base DDEV locale)
./Tests/Scripts/cleanup_database.sh --min-age=30

# Extraire + anonymiser
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200

# Vérifier l'anonymisation avant commit
grep -r '@' Tests/Fixtures/Database --include='*.csv' | grep -v '@example.com'

# Commiter les fixtures mises à jour
git add Tests/Fixtures/Database/
git commit -m "fix(fixtures): update anonymized CSV"

# Régénérer les snapshots locaux
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...
```

## Documentation complète

→ [TYPO3-HEADLESS-VALIDATION.md](./TYPO3-HEADLESS-VALIDATION.md)
