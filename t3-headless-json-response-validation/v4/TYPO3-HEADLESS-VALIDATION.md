# Stratégie de validation JSON — TYPO3 Headless v13

> Documentation pour les équipes **backend** et **frontend** d'un projet TYPO3 v13 headless
> de type [pwa-demo](https://github.com/TYPO3-Headless/pwa-demo) (TYPO3 + Vue.js / Nuxt).

---

## Table des matières

1. [Principe fondamental](#1-principe-fondamental)
2. [Contraintes et solutions](#2-contraintes-et-solutions)
3. [Les 4 piliers de la validation](#3-les-4-piliers-de-la-validation)
4. [Structure des fichiers](#4-structure-des-fichiers)
5. [Guide développeur Backend](#5-guide-développeur-backend)
6. [Guide développeur Frontend](#6-guide-développeur-frontend)
7. [Intégration Playwright](#7-intégration-playwright)
8. [Workflow Git collaboratif](#8-workflow-git-collaboratif)
9. [Pipeline CI/CD](#9-pipeline-cicd)
10. [Commandes de référence](#10-commandes-de-référence)
11. [FAQ](#11-faq)

---

## 1. Principe fondamental

### AUCUNE DONNÉE DANS GIT

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DANS GIT ✅                                  │
│  Tests/Fixtures/Schemas/      → structure JSON (aucune donnée)      │
│  Tests/Functional/Headless/   → code PHP (aucune donnée)            │
│  Tests/Scripts/               → scripts shell (aucune donnée)       │
│  .gitignore  .gitlab-ci.yml   → infrastructure                      │
├─────────────────────────────────────────────────────────────────────┤
│                      PAS DANS GIT ❌                                 │
│  Tests/Fixtures/Database/     → fixtures CSV  (générées localement) │
│  Tests/Fixtures/Snapshots/    → réponses JSON (générées localement) │
└─────────────────────────────────────────────────────────────────────┘
```

Ce principe est **absolu**. Il s'applique même aux données entièrement synthétiques car :

- Les fixtures CSV reflètent la **structure réelle** de la base TYPO3
- Les snapshots contiennent des **réponses JSON réelles** de l'API (titres, slugs, méta)
- Tout fichier commité dans Git **reste dans l'historique à jamais**
- La conformité RGPD exige une traçabilité — le dépôt Git n'est pas un registre RGPD

### Comment les données circulent

```
Base production (1,3 Go — RGPD)
      │
      │  cleanup_database.sh         generate_fixtures.sh
      │  + extract_and_anonymize.sh  (mode synthétique hors-ligne)
      ▼
Tests/Fixtures/Database/          Tests/Fixtures/Schemas/
(gitignored — local & CI)         (dans Git — structure uniquement)
      │                                    │
      └──────────────┬─────────────────────┘
                     ▼
            PHPUnit FunctionalTestCase
                     │
                     ▼
         Tests/Fixtures/Snapshots/
         (gitignored — local & CI)
```

---

## 2. Contraintes et solutions

| Contrainte | Solution |
|---|---|
| Base 1,3 Go impossible à versionner | Extraction de ~50 Ko représentatifs par scénario |
| Données sensibles RGPD | Fixtures **jamais** dans Git (gitignorées) |
| Soft-deletes TYPO3 (milliers de `deleted=1`) | `cleanup_database.sh` + `deleted=0` forcé dans toutes les requêtes |
| FE users et endpoints protégés | 3 comptes de test synthétiques (standard/premium/admin) |
| Travail hors-ligne (TGV, avion) | `generate_fixtures.sh` — zéro connexion réseau requise |
| Tests reproductibles | UIDs stables (1–10), `crdate=0`, `tstamp=0` |
| CI/CD isolé | CI génère les fixtures à la volée via `generate_fixtures.sh` |
| Performance | Tests via `executeFrontendSubRequest()` — pas de serveur HTTP |

---

## 3. Les 4 piliers de la validation

### Pilier 1 — Fixtures CSV (gitignorées, générées localement)

Données minimales représentatives. **Jamais dans Git.**

**5 scénarios :**

| Scénario | UID | Tables | Cas couvert |
|---|---|---|---|
| `page_simple` | 1 | pages | Page publique basique |
| `page_with_content` | 2 | pages, tt_content | Contenu texte multi-éléments |
| `page_with_images` | 3 | pages, tt_content, sys_file, sys_file_reference | Images FAL |
| `page_with_categories` | 4 | pages, tt_content, sys_category, sys_category_record_mm | Catégories |
| `page_protected` | 5 | pages, tt_content, fe_groups, fe_users | Authentification FE |

**FE users de test (synthétiques — jamais extraits de la prod) :**

| UID | Username | Groupes | Rôle |
|---|---|---|---|
| 100 | `test_standard` | 1 | Accès standard |
| 101 | `test_premium` | 1,2 | Accès premium |
| 102 | `test_admin` | 1,2,3 | Accès admin |

Mot de passe : **`password`** pour tous (hash bcrypt TYPO3 dans les CSV locaux).

**Deux modes de génération — jamais dans Git dans les deux cas :**

```bash
# Mode A — Synthétique (recommandé : CI, hors-ligne, nouveaux développeurs)
./Tests/Scripts/generate_fixtures.sh

# Mode B — Extraction depuis la base DDEV locale
./Tests/Scripts/cleanup_database.sh          # purge soft-deletes TYPO3
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200
```

**Règles communes :**

- UIDs stables : pages 1–5, tt_content 10–41, fe_users 100–102
- `deleted=0`, `hidden=0` partout
- Champs dynamiques à zéro : `crdate=0`, `tstamp=0`, `lastUpdated=0`
- Aucun email hors `@example.com`, aucun téléphone réel

### Pilier 2 — JSON Schemas partiels (dans Git — aucune donnée)

Un schema par zone de réponse, référencés via `$ref`. **Structure uniquement.**

```
Tests/Fixtures/Schemas/                     ← dans Git ✅
├── partials/
│   ├── meta.schema.json        → SEO : title, robots, canonical, og:*
│   ├── i18n.schema.json        → locale, hreflang, alternates
│   ├── breadcrumbs.schema.json → fil d'Ariane : link, title, current
│   ├── appearance.schema.json  → layout, backendLayout
│   └── content.schema.json     → colPos + éléments de contenu
└── page_*.schema.json          → schema principal par scénario
```

`additionalProperties: true` partout pour absorber les nouveaux champs TYPO3 sans casser les tests.

### Pilier 3 — Snapshots JSON (gitignorés, générés localement)

Photographies de la réponse réelle — détectent les régressions. **Jamais dans Git.**

Un snapshot global + 5 partiels par zone = 30 fichiers pour 5 scénarios.

```bash
# Générer / régénérer
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless
```

Les snapshots partiels par zone permettent des diffs ciblés : si seule `breadcrumbs.json` change, on sait exactement quelle zone est affectée.

### Pilier 4 — FunctionalTestCase TYPO3 v13 (dans Git — aucune donnée)

7 méthodes par scénario public, méthodes d'authentification supplémentaires pour `page_protected` :

```
# Scénarios publics (7 méthodes chacun)
jsonResponseMatchesGlobalSchema()
jsonResponseMatchesGlobalSnapshot()
metaZoneMatchesSchemaAndSnapshot()        ← rules métier SEO
i18nZoneMatchesSchemaAndSnapshot()        ← locale, hreflang
breadcrumbsZoneMatchesSchemaAndSnapshot() ← racine=/, dernier=current
appearanceZoneMatchesSchemaAndSnapshot()
contentZoneMatchesSchemaAndSnapshot()

# Page protégée (méthodes supplémentaires)
unauthenticatedAccessIsDenied()           ← HTTP 302/403
standardUserCanAccessProtectedPage()      ← fe_user uid=100
premiumUserSeesFullContent()              ← fe_user uid=101
adminUserCanAccessProtectedPage()         ← fe_user uid=102
```

---

## 4. Structure des fichiers

```
Tests/
├── Functional/Headless/                    ✅ Git
│   ├── AbstractHeadlessTestCase.php
│   ├── PageSimpleTest.php
│   ├── PageWithContentTest.php
│   ├── PageWithImagesTest.php
│   ├── PageWithCategoriesTest.php
│   └── PageProtectedTest.php
│
├── Fixtures/
│   ├── Database/                           ❌ gitignored
│   │   ├── shared/{fe_groups,fe_users}.csv
│   │   ├── page_simple/pages.csv
│   │   ├── page_with_content/{pages,tt_content}.csv
│   │   ├── page_with_images/{pages,tt_content,sys_file,sys_file_reference}.csv
│   │   ├── page_with_categories/{pages,tt_content,sys_category,mm}.csv
│   │   └── page_protected/{pages,tt_content,fe_groups,fe_users}.csv
│   │
│   ├── Schemas/                            ✅ Git
│   │   ├── partials/{meta,i18n,breadcrumbs,appearance,content}.schema.json
│   │   └── page_{simple,with_content,with_images,with_categories,protected}.schema.json
│   │
│   └── Snapshots/                          ❌ gitignored
│       ├── page_with_content.json
│       ├── page_with_content.{meta,i18n,breadcrumbs,appearance,content}.json
│       └── ... (6 fichiers × 5 scénarios = 30 fichiers)
│
└── Scripts/                                ✅ Git
    ├── cleanup_database.sh     → purge soft-deletes TYPO3 (base DDEV locale)
    ├── extract_and_anonymize.sh → extraction + anonymisation depuis DDEV
    ├── generate_fixtures.sh    → génération synthétique (CI / hors-ligne)
    ├── generate_schemas.sh     → génère les schemas partiels
    ├── generate_headless_tests.sh → génère les tests PHP
    ├── update_snapshots.sh     → wrapper UPDATE_SNAPSHOTS=1
    └── verify_snapshots.sh     → vérification intégrité (CI pre-check)
```

---

## 5. Guide développeur Backend

### Installation initiale

```bash
# 1. Dépendances
composer require --dev typo3/testing-framework:"^8.0" justinrainbow/json-schema

# 2. Hooks Git (bloquent toute donnée dans Git)
chmod +x setup-git-hooks.sh Tests/Scripts/*.sh
./setup-git-hooks.sh

# 3. Générer les fixtures LOCALES (gitignorées)
./Tests/Scripts/generate_fixtures.sh            # Mode A : synthétique (recommandé)

# OU avec DDEV (Mode B)
./Tests/Scripts/cleanup_database.sh             # purge soft-deletes
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200

# 4. Générer les snapshots locaux (gitignorés)
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# 5. Lancer les tests
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless --testdox

# 6. Vérifier que git status est propre
git status  # Database/ et Snapshots/ NE doivent PAS apparaître
```

### Après une modification TYPO3

```bash
# Régénérer les fixtures locales
./Tests/Scripts/generate_fixtures.sh

# Régénérer les snapshots locaux
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...

# Si la structure de la réponse change → mettre à jour le schema
vim Tests/Fixtures/Schemas/partials/<zone>.schema.json
git add Tests/Fixtures/Schemas/
git commit -m "feat(api): description du changement"
```

### Soft-deletes — workflow complet

```bash
./Tests/Scripts/cleanup_database.sh --dry-run   # simulation
./Tests/Scripts/cleanup_database.sh --min-age=30  # purge réelle (DDEV local)
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200
./Tests/Scripts/generate_fixtures.sh              # OU synthétique
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...
```

---

## 6. Guide développeur Frontend

### Types TypeScript depuis les schemas

```bash
npm install -D json-schema-to-typescript

# Schemas dans Git → disponibles dès git clone
npx json-schema-to-typescript \
  Tests/Fixtures/Schemas/partials/*.schema.json \
  -o front/src/types/api/
```

### Snapshots comme mocks Vitest

Les snapshots sont gitignorés. Options pour les obtenir :

```bash
# Option 1 : générer localement
./Tests/Scripts/generate_fixtures.sh
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...

# Option 2 : artifacts CI (GitLab → CI/CD → Pipelines → télécharger)
```

```typescript
import pageSnapshot from '../../../Tests/Fixtures/Snapshots/page_with_content.json'

test('affiche le titre', () => {
  const wrapper = mount(PageContent, { props: { page: pageSnapshot } })
  expect(wrapper.text()).toContain(pageSnapshot.meta.title)
})
```

### Validation légère sans PHPUnit

```bash
# Valide les endpoints réels contre les schemas (schemas dans Git)
./front/scripts/validate-api.sh http://localhost:8080
```

---

## 7. Intégration Playwright

```typescript
// playwright/tests/headless-json.spec.ts
import * as fs from 'fs'

// Snapshots gitignorés — récupérés depuis artifacts CI ou génération locale
const snapshot = JSON.parse(
  fs.readFileSync('Tests/Fixtures/Snapshots/page_with_content.json', 'utf-8')
)

test('titre SEO correct', async ({ page }) => {
  await page.goto(snapshot.slug)
  await expect(page).toHaveTitle(new RegExp(snapshot.meta.title))
})

test('fe_user standard accède à la page protégée', async ({ page }) => {
  await page.goto('/login')
  await page.fill('[name="user"]', 'test_standard')
  await page.fill('[name="pass"]', 'password')
  await page.click('[type="submit"]')
  await page.goto('/test-protected-page')
  await expect(page.locator('[data-testid="content-element"]')).toBeVisible()
})
```

---

## 8. Workflow Git collaboratif

### Règle absolue

```bash
git add Tests/Fixtures/Database/    # ❌ bloqué par pre-commit hook
git add Tests/Fixtures/Snapshots/  # ❌ bloqué par pre-commit hook
git add Tests/Fixtures/Schemas/    # ✅ OK — structure uniquement
git add Tests/Scripts/             # ✅ OK — code sans données
git add Tests/Functional/          # ✅ OK — code sans données
```

### Cycle backend → frontend

```
Backend modifie TYPO3
  │
  ├─ Si schema change → git commit Tests/Fixtures/Schemas/
  ├─ Localement : generate_fixtures.sh + UPDATE_SNAPSHOTS=1 (pas de commit)
  └─ Push → CI génère fixtures synthétiques → tests

Frontend reçoit le push
  ├─ Hook post-merge : "Schemas modifiés → régénérer les types TS"
  ├─ npx json-schema-to-typescript ...
  └─ Mise à jour des composants Vue
```

### Conventions de commits

```bash
# Non-breaking
git commit -m "feat(api): add optional subtitle to content schema"

# Breaking
git commit -m "feat(api)!: rename bodytext to body

BREAKING CHANGE: bodytext → body dans content.schema.json
Frontend : mettre à jour TextElement.vue, RichText.vue
Types TS : régénérer avec json-schema-to-typescript"
```

---

## 9. Pipeline CI/CD

Le CI génère ses propres fixtures synthétiques à chaque pipeline. Aucune base de production, aucun artifact permanent de données.

```
prepare:fixtures-and-snapshots
  ├─ generate_fixtures.sh          (synthétique, ~2s)
  ├─ UPDATE_SNAPSHOTS=1 phpunit    (génération snapshots)
  ├─ verify_snapshots.sh           (intégrité)
  ├─ artifacts: expire_in: 1 hour
  └─ after_script: rm -rf Database/ Snapshots/

test:headless
  ├─ consomme artifacts prepare
  ├─ vendor/bin/phpunit (35 tests)
  └─ after_script: rm -rf Database/ Snapshots/
```

**Variables GitLab requises (masked) :** `SLACK_WEBHOOK_URL`, `typo3DatabasePassword`

---

## 10. Commandes de référence

```bash
# Cycle complet après git clone
composer install && chmod +x setup-git-hooks.sh Tests/Scripts/*.sh
./setup-git-hooks.sh
./Tests/Scripts/generate_fixtures.sh
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless
vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless --testdox
git status   # doit être propre

# Soft-deletes TYPO3
./Tests/Scripts/cleanup_database.sh --dry-run
./Tests/Scripts/cleanup_database.sh --min-age=30
ddev exec vendor/bin/typo3 cleanup:deletedrecords --min-age=30
ddev exec vendor/bin/typo3 cleanup:missingrelations --update-refindex
ddev exec vendor/bin/typo3 referenceindex:update

# Vérification sécurité
git ls-files Tests/Fixtures/Database/   # doit être vide
git ls-files Tests/Fixtures/Snapshots/  # doit être vide
```

---

## 11. FAQ

**Q : Nouveau développeur — comment démarrer ?**
```bash
git clone <repo> && composer install
chmod +x setup-git-hooks.sh Tests/Scripts/*.sh && ./setup-git-hooks.sh
./Tests/Scripts/generate_fixtures.sh
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless
vendor/bin/phpunit ... --testdox
```

**Q : Je travaille dans le TGV — comment lancer les tests sans connexion ?**
`generate_fixtures.sh` génère des données entièrement synthétiques sans aucun accès réseau. Après `git clone + composer install`, c'est la seule commande requise avant les tests.

**Q : Comment partager mes snapshots avec un collègue ?**
Chaque développeur génère les siens en ~10 secondes. Les schemas dans Git garantissent une structure identique. En CI, les snapshots sont des artifacts éphémères téléchargeables.

**Q : Un test échoue car les snapshots sont absents**
```bash
./Tests/Scripts/generate_fixtures.sh
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless
```

**Q : Des données ont été commitées par erreur**
```bash
git rm --cached -r Tests/Fixtures/Database/ Tests/Fixtures/Snapshots/
git commit -m "fix: remove data files from Git"
# Si données sensibles dans l'historique :
pip install git-filter-repo
git filter-repo --path Tests/Fixtures/Database/ --invert-paths
# Contacter le DPO si des données personnelles réelles étaient concernées
```

**Q : Puis-je commiter les fixtures pour "gagner du temps" ?**
Non. Le principe est absolu. `generate_fixtures.sh` s'exécute en moins de 2 secondes. Le risque RGPD d'un commit accidentel de données est sans commune mesure avec ce gain.

**Q : La page protégée retourne 403 même avec fe_user**
Vérifier que `fe_groups.csv` est importé **avant** `fe_users.csv` (dépendance FK). Vérifier que le champ `fe_group` de la page correspond à un UID de groupe présent dans les fixtures.

---

*Dernière mise à jour : février 2026 — TYPO3 v13 / EXT:headless v4 / PHP 8.2*
