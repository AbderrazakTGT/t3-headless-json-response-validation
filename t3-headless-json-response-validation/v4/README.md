# TYPO3 Headless — Stratégie de validation JSON

Tests PHPUnit pour valider les endpoints JSON d'un projet TYPO3 v13 headless.

## Principe fondamental : aucune donnée dans Git

```
Git contient :          Git ne contient PAS :
✅ Code PHP             ❌ Tests/Fixtures/Database/  (CSV fixtures)
✅ JSON Schemas         ❌ Tests/Fixtures/Snapshots/ (JSON snapshots)
✅ Scripts shell
✅ CI/CD config
```

Les fixtures et snapshots sont **générés localement** par chaque développeur
et dans le CI **à la volée**. Aucune donnée réelle, aucune donnée anonymisée
ne transite par Git.

## Démarrage rapide

```bash
# 1. Cloner et installer
git clone <repo> && composer install

# 2. Hooks Git (une seule fois)
chmod +x setup-git-hooks.sh && ./setup-git-hooks.sh

# 3. Générer les fixtures locales (deux options)

# Option A — synthétique, hors-ligne, CI (recommandé)
chmod +x Tests/Scripts/*.sh
./Tests/Scripts/generate_fixtures.sh

# Option B — extraction depuis DDEV (base locale)
./Tests/Scripts/cleanup_database.sh     # purge soft-deletes TYPO3
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200

# 4. Générer les snapshots locaux
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# 5. Lancer les tests
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless --testdox
```

## Ce qui est généré localement (jamais commité)

```
Tests/Fixtures/Database/        ← generate_fixtures.sh ou extract_and_anonymize.sh
├── shared/fe_groups.csv
├── shared/fe_users.csv         ← 3 rôles, mdp: "password"
├── page_simple/pages.csv
├── page_with_content/{pages,tt_content}.csv
├── page_with_images/{pages,tt_content,sys_file,sys_file_reference}.csv
├── page_with_categories/{pages,tt_content,sys_category,mm}.csv
└── page_protected/{pages,tt_content,fe_groups,fe_users}.csv

Tests/Fixtures/Snapshots/       ← UPDATE_SNAPSHOTS=1 vendor/bin/phpunit
├── page_with_content.json
├── page_with_content.meta.json
└── ... (global + 5 partiels × 5 scénarios)
```

## Scénarios de test

| Scénario | Page UID | Cas couvert |
|---|---|---|
| `page_simple` | 1 | Page publique basique |
| `page_with_content` | 2 | Contenu texte multi-éléments |
| `page_with_images` | 3 | Images FAL (sys_file) |
| `page_with_categories` | 4 | Catégories TYPO3 |
| `page_protected` | 5 | Authentification FE user |

## FE users de test (générés, jamais dans Git)

| UID | Username | Rôle | Mot de passe |
|---|---|---|---|
| 100 | `test_standard` | Groupe 1 | `password` |
| 101 | `test_premium` | Groupes 1+2 | `password` |
| 102 | `test_admin` | Groupes 1+2+3 | `password` |

## Documentation complète

→ [TYPO3-HEADLESS-VALIDATION.md](./TYPO3-HEADLESS-VALIDATION.md)
