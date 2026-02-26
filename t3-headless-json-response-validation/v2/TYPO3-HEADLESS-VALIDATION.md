# Stratégie de validation JSON — TYPO3 Headless

> Documentation à destination des équipes **backend** et **frontend** pour un projet TYPO3 v13 headless de type [pwa-demo](https://github.com/TYPO3-Headless/pwa-demo) (TYPO3 + Vue.js / Nuxt).
>
> ⚠️ **Contraintes de sécurité actives** : base de production 1,3 Go avec données sensibles (RGPD). Aucune donnée réelle ne doit être versionnée. Les fixtures sont anonymisées et les snapshots sont générés localement.

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture du projet](#2-architecture-du-projet)
3. [Les 4 piliers de la validation](#3-les-4-piliers-de-la-validation)
4. [Adaptation sécurité & RGPD](#4-adaptation-sécurité--rgpd)
5. [Structure des fichiers](#5-structure-des-fichiers)
6. [Guide développeur Backend](#6-guide-développeur-backend)
7. [Guide développeur Frontend](#7-guide-développeur-frontend)
8. [Intégration Playwright](#8-intégration-playwright)
9. [Workflow Git collaboratif](#9-workflow-git-collaboratif)
10. [Pipeline CI/CD](#10-pipeline-cicd)
11. [Commandes de référence](#11-commandes-de-référence)
12. [FAQ et résolution de problèmes](#12-faq-et-résolution-de-problèmes)

---

## 1. Vue d'ensemble

Dans un projet TYPO3 headless, le backend expose des **pages complètes en JSON** consommées par un frontend découplé (Vue.js / Nuxt). Chaque réponse contient plusieurs zones distinctes : `meta` (SEO), `i18n` (langues), `breadcrumbs`, `appearance` (layout), `content` (colPos).

Le JSON est le seul point de contact entre les deux équipes. Cette stratégie le valide à deux niveaux :

```
Base de production (1,3 Go — DONNÉES SENSIBLES)
      │
      │  Script d'anonymisation
      ▼
Fixtures CSV anonymisées        JSON Schemas partiels
(générées localement,           (versionnés dans Git)
 jamais dans Git)                     │
      │                               │
      ▼                               ▼
FunctionalTestCase TYPO3  ──────► Validation
      │
      ▼
Snapshots JSON                  CI/CD GitLab
(générés localement,            (génère les fixtures
 jamais dans Git)                à la volée, sans données
                                 de production)
```

### Ce qui est versionné dans Git

| Fichier | Versionné | Raison |
|---|---|---|
| `Tests/Scripts/*.sh` | ✅ oui | scripts sans données |
| `Tests/Fixtures/Schemas/**/*.schema.json` | ✅ oui | contrat JSON sans données |
| `Tests/Functional/Headless/*.php` | ✅ oui | code de test sans données |
| `Tests/Fixtures/Database/**/*.csv` | ❌ **non** | données anonymisées générées localement |
| `Tests/Fixtures/Snapshots/**/*.json` | ❌ **non** | contiennent des données de page |
| `.gitignore` | ✅ oui | définit les exclusions |

---

## 2. Architecture du projet

```
pwa-demo/
├── config/           → configuration TYPO3 (sites, extensions)
├── data/             → base de données et fichiers uploadés (hors Git)
├── front/            → application Vue.js / Nuxt
│   ├── components/
│   ├── pages/
│   ├── composables/
│   └── tests/        → tests Vitest + Playwright
└── packages/
    └── site_package/ → extension TYPO3 custom
        └── Tests/    → tests PHPUnit (cette stratégie)
```

---

## 3. Les 4 piliers de la validation

### Pilier 1 — Les fixtures CSV (anonymisées, générées localement)

Les fixtures alimentent la base de test avec des données **synthétiques et anonymisées**. Elles ne proviennent **jamais** directement de la base de production. Deux modes de génération :

**Mode A — Génération synthétique pure** (recommandé pour le CI) : les fixtures sont créées de zéro par `generate_fixtures.sh` avec des données fictives mais réalistes. Aucun accès à la base de production nécessaire.

**Mode B — Extraction + anonymisation** (pour les développeurs qui veulent coller à la réalité) : `extract_and_anonymize.sh` extrait des lignes de la base locale DDEV, remplace toutes les données personnelles, fixe les UIDs.

Règles communes :
- UIDs fixes et petits (1–10) pour la reproductibilité
- Aucun champ dynamique : pas de `crdate`, `tstamp`, `lastUpdated`
- Aucun email, téléphone, nom réel, adresse IP
- Fichiers générés dans `Tests/Fixtures/Database/` — listés dans `.gitignore`

### Pilier 2 — Les JSON Schemas partiels (versionnés)

Un schema par zone de la réponse, réutilisable entre tous les scénarios via `$ref`. Les schemas ne contiennent aucune donnée — ils définissent uniquement la structure et les types attendus.

```
Tests/Fixtures/Schemas/
├── partials/
│   ├── meta.schema.json         → SEO (title, robots, canonical, og:*)
│   ├── i18n.schema.json         → langue, locale, hreflang, alternates
│   ├── breadcrumbs.schema.json  → fil d'Ariane
│   ├── appearance.schema.json   → layout, backendLayout
│   └── content.schema.json      → colPos, éléments de contenu
└── page_with_content.schema.json → schema principal ($ref vers partiels)
```

### Pilier 3 — Les snapshots JSON (générés localement, non versionnés)

Les snapshots sont des photographies de la réponse JSON de référence. Ils sont générés localement par PHPUnit et stockés dans `Tests/Fixtures/Snapshots/` — répertoire listé dans `.gitignore`.

Pour partager les snapshots entre développeurs sans Git, deux mécanismes sont prévus :
- **Artifact CI** : le pipeline génère et publie les snapshots en artifacts téléchargeables
- **Template de snapshot** : un snapshot "vide" versionné par zone, à remplir localement

### Pilier 4 — Le FunctionalTestCase TYPO3 (versionné)

Le code PHP de test est versionné. Il ne contient aucune donnée. Il valide 7 zones par scénario :

```
setUp()                      → importe les CSV anonymisés (générés localement)
executeFrontendSubRequest()  → appelle TYPO3 en interne (pas de curl)
assertMatchesJsonSchema()    → valide la structure contre le schema
assertPartialSnapshot()      → compare par zone (meta, i18n, breadcrumbs...)
assertValidMetaZone()        → règles métier SEO
assertValidI18nZone()        → règles métier internationalisation
assertValidBreadcrumbsZone() → règles métier fil d'Ariane
assertValidContentZone()     → règles métier contenu colPos
tearDown()                   → détruit la DB temporaire
```

---

## 4. Adaptation sécurité & RGPD

### Ce qui est interdit

- Versionner des dumps de la base de production, même partiels
- Versionner des emails, noms, téléphones, adresses, UIDs de vrais utilisateurs
- Commiter des snapshots contenant des métadonnées de pages réelles (titres, slugs, descriptions avec noms propres)
- Stocker des credentials de base de données dans les scripts versionnés

### Règles d'anonymisation appliquées par les scripts

| Champ | Règle |
|---|---|
| `title` | Remplacé par "Test Page [N]" |
| `bodytext` contenant des noms | Remplacé par Lorem Ipsum |
| `email` | Remplacé par `test-[n]@example.com` |
| `phone` | Remplacé par `+33 0 00 00 00 [n]` |
| `slug` | Normalisé `/test-page-[n]` |
| `crdate`, `tstamp` | Supprimés du CSV |
| `fe_users.*` | Table entièrement exclue |
| UIDs | Réassignés à 1, 2, 3... |

### Configuration .gitignore

```gitignore
# Données de test — jamais dans Git
Tests/Fixtures/Database/
Tests/Fixtures/Snapshots/

# Environnement local
.env.local
.env.test.local

# Credentials DDEV
.ddev/config.yaml.local
```

---

## 5. Structure des fichiers

```
Tests/
├── Functional/
│   └── Headless/
│       ├── AbstractHeadlessTestCase.php    ← versionné — classe de base
│       ├── PageSimpleTest.php              ← versionné
│       ├── PageWithContentTest.php         ← versionné
│       ├── PageWithImagesTest.php          ← versionné
│       └── PageWithCategoriesTest.php      ← versionné
│
├── Fixtures/
│   ├── Database/                           ← gitignored — générés localement
│   │   ├── page_simple/pages.csv
│   │   ├── page_with_content/{pages,tt_content}.csv
│   │   ├── page_with_images/{pages,tt_content,sys_file,sys_file_reference}.csv
│   │   └── page_with_categories/{pages,tt_content,sys_category,sys_category_record_mm}.csv
│   │
│   ├── Schemas/                            ← versionné — aucune donnée
│   │   ├── partials/
│   │   │   ├── meta.schema.json
│   │   │   ├── i18n.schema.json
│   │   │   ├── breadcrumbs.schema.json
│   │   │   ├── appearance.schema.json
│   │   │   └── content.schema.json
│   │   ├── page_simple.schema.json
│   │   ├── page_with_content.schema.json
│   │   ├── page_with_images.schema.json
│   │   └── page_with_categories.schema.json
│   │
│   └── Snapshots/                          ← gitignored — générés localement
│       ├── page_with_content.json
│       ├── page_with_content.meta.json
│       ├── page_with_content.i18n.json
│       ├── page_with_content.breadcrumbs.json
│       ├── page_with_content.appearance.json
│       └── page_with_content.content.json
│       └── ... (idem autres scénarios)
│
└── Scripts/                                ← versionné — scripts sans données
    ├── generate_fixtures.sh                ← génère les CSV synthétiques
    ├── extract_and_anonymize.sh            ← extrait + anonymise depuis DDEV
    ├── generate_schemas.sh                 ← génère les schemas partiels
    ├── generate_headless_tests.sh          ← génère les fichiers PHP
    ├── update_snapshots.sh                 ← régénère les snapshots
    └── verify_snapshots.sh                 ← vérifie les snapshots
```

---

## 6. Guide développeur Backend

### Installation initiale

```bash
# 1. Installer les dépendances
composer require --dev typo3/testing-framework:"^8.0" justinrainbow/json-schema

# 2. Générer les schemas (versionnés, à faire une seule fois)
chmod +x Tests/Scripts/*.sh
./Tests/Scripts/generate_schemas.sh
./Tests/Scripts/generate_headless_tests.sh

# 3. Générer les fixtures CSV locales (deux options)

# Option A — synthétique (recommandé, pas besoin de la base de prod)
./Tests/Scripts/generate_fixtures.sh

# Option B — extraction anonymisée depuis DDEV
# (nécessite que DDEV soit démarré avec la base de production importée)
./Tests/Scripts/extract_and_anonymize.sh

# 4. Générer les snapshots initiaux
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# 5. Lancer les tests (mode vérification)
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless --testdox

# 6. Commiter uniquement les fichiers versionnés
git add Tests/Functional/ Tests/Fixtures/Schemas/ Tests/Scripts/
git status  # vérifier qu'aucun CSV ni snapshot n'est stagé
git commit -m "feat: add headless JSON validation tests"
```

### Ajouter un nouveau type de contenu

```bash
# 1. Modifier Tests/Scripts/generate_fixtures.sh pour inclure les nouveaux CTypes
# 2. Régénérer les fixtures
./Tests/Scripts/generate_fixtures.sh

# 3. Mettre à jour le schema partiel concerné
# (ex: Tests/Fixtures/Schemas/partials/content.schema.json)

# 4. Régénérer les snapshots
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# 5. Vérifier les diffs par zone
git diff Tests/Fixtures/Schemas/

# 6. Commiter uniquement les schemas modifiés (pas les snapshots, pas les CSV)
git add Tests/Fixtures/Schemas/
git commit -m "feat(api): add accordion content type to content schema"
```

### Workflow quotidien

```bash
# Matin : vérifier que les tests passent toujours
vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless

# Après un changement TYPO3 : régénérer les snapshots
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...

# Inspecter ce qui a changé par zone
diff Tests/Fixtures/Snapshots/page_with_content.meta.json /tmp/prev_meta.json
```

---

## 7. Guide développeur Frontend

Le frontend ne touche pas aux fixtures ni aux tests PHPUnit. Il consomme les **schemas versionnés** et utilise les **snapshots locaux** comme mocks.

### Génération des types TypeScript

```bash
# Dans le dossier front/
npm install -D json-schema-to-typescript

# Générer les types depuis les schemas versionnés
npx json-schema-to-typescript \
  ../Tests/Fixtures/Schemas/partials/*.schema.json \
  -o src/types/api/
```

Résultat dans `front/src/types/api/` :

```typescript
// meta.d.ts — généré automatiquement depuis meta.schema.json
export interface Meta {
  title: string;
  description?: string;
  ogTitle?: string;
  ogImage?: string;   // commence par /fileadmin/
  robots: string;     // pattern: index|noindex,follow|nofollow
  canonical?: string; // URL absolue
}
```

### Utiliser les snapshots locaux comme mocks Vitest

Les snapshots locaux (non versionnés) servent de fixtures pour les tests Vitest :

```typescript
// front/tests/unit/PageContent.test.ts
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import PageContent from '~/components/PageContent.vue'
import { readFileSync } from 'fs'
import { resolve } from 'path'

// Charge le snapshot local (non versionné — généré par le backend)
const snapshotPath = resolve(__dirname, '../../../Tests/Fixtures/Snapshots/page_with_content.json')
const pageSnapshot = JSON.parse(readFileSync(snapshotPath, 'utf-8'))

describe('PageContent', () => {
  it('affiche le titre de la page', () => {
    const wrapper = mount(PageContent, { props: { page: pageSnapshot } })
    expect(wrapper.text()).toContain(pageSnapshot.title)
  })

  it('affiche les éléments de colPos0', () => {
    const wrapper = mount(PageContent, { props: { page: pageSnapshot } })
    const count = pageSnapshot.content.colPos0.length
    expect(wrapper.findAll('[data-testid="content-element"]')).toHaveLength(count)
  })

  it('applique la meta robots correcte', () => {
    expect(pageSnapshot.meta.robots).toMatch(/^(index|noindex),(follow|nofollow)$/)
  })
})
```

### Script de validation API légère (sans PHPUnit)

Pour valider rapidement l'API depuis le frontend sans lancer PHPUnit :

```bash
# front/scripts/validate-api.sh
# Valide la structure JSON de l'API contre les schemas versionnés
BASE_URL=${1:-"http://localhost"}

for schema in ../Tests/Fixtures/Schemas/*.schema.json; do
  scenario=$(basename "$schema" .schema.json)
  echo "Validation : $scenario"
  curl -s "$BASE_URL/api/pages/$scenario" | \
    npx ajv validate -s "$schema" -d - && \
    echo "✓ $scenario" || echo "✗ $scenario FAILED"
done
```

### Surveiller les changements de schemas

```bash
# Hook post-merge dans .git/hooks/post-merge
#!/bin/bash
changed=$(git diff HEAD@{1} HEAD --name-only | grep "Tests/Fixtures/Schemas/")
if [ -n "$changed" ]; then
  echo ""
  echo "⚠️  SCHEMAS JSON modifiés — régénérer les types TypeScript :"
  echo "$changed" | sed 's/^/   - /'
  echo ""
  echo "   cd front && npx json-schema-to-typescript ../Tests/Fixtures/Schemas/partials/*.schema.json -o src/types/api/"
fi
```

---

## 8. Intégration Playwright

Le repo Playwright dédié s'intègre à cette stratégie de deux façons.

### Utiliser les snapshots comme données de test E2E

```typescript
// playwright/tests/page-content.spec.ts
import { test, expect } from '@playwright/test'
import { readFileSync } from 'fs'

const snapshot = JSON.parse(
  readFileSync('../../Tests/Fixtures/Snapshots/page_with_content.json', 'utf-8')
)

test('la page affiche le bon titre SEO', async ({ page }) => {
  await page.goto(snapshot.slug)
  await expect(page).toHaveTitle(snapshot.meta.title)
})

test('le fil d\'Ariane est complet', async ({ page }) => {
  await page.goto(snapshot.slug)
  const breadcrumbs = page.locator('[data-testid="breadcrumb-item"]')
  await expect(breadcrumbs).toHaveCount(snapshot.breadcrumbs.length)
})

test('tous les éléments de contenu sont rendus', async ({ page }) => {
  await page.goto(snapshot.slug)
  const elements = page.locator('[data-testid="content-element"]')
  await expect(elements).toHaveCount(snapshot.content.colPos0.length)
})
```

### Valider les headers HTTP en parallèle

```typescript
// playwright/tests/api-headers.spec.ts
test('les headers Content-Type et Cache-Control sont corrects', async ({ request }) => {
  const response = await request.get('/api/pages/2')

  expect(response.headers()['content-type']).toContain('application/json')
  expect(response.status()).toBe(200)

  const body = await response.json()
  expect(body).toHaveProperty('meta')
  expect(body).toHaveProperty('content')
})
```

### Workflow combiné PHPUnit + Playwright

```
PHPUnit (Tests/Functional/Headless/)
  → valide la structure JSON (schemas + snapshots)
  → s'exécute sans navigateur, sans serveur

Playwright (repo dédié)
  → valide le rendu visuel dans le navigateur
  → utilise les snapshots PHPUnit comme source de vérité
  → s'exécute avec un serveur Nuxt + TYPO3 actifs
```

---

## 9. Workflow Git collaboratif

### Ce qui est commité, ce qui ne l'est pas

```
Git repository
├── ✅ Tests/Scripts/*.sh                  → scripts versionnés
├── ✅ Tests/Fixtures/Schemas/**           → contrats versionnés
├── ✅ Tests/Functional/Headless/*.php     → code versionné
├── ❌ Tests/Fixtures/Database/            → gitignored
└── ❌ Tests/Fixtures/Snapshots/           → gitignored
```

### Cycle de vie d'un changement de contrat

```
Backend modifie TYPO3
      │
      ├── Met à jour Tests/Fixtures/Schemas/ (si structure change)
      ├── Met à jour Tests/Scripts/generate_fixtures.sh (si nouveau champ)
      ├── Régénère localement les fixtures : ./Tests/Scripts/generate_fixtures.sh
      ├── Régénère localement les snapshots : UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...
      ├── Vérifie les tests : vendor/bin/phpunit ...
      └── Commit + Push : uniquement Scripts/ et Schemas/
                │
                ▼
          CI génère ses propres fixtures à la volée
          CI exécute les tests contre les schemas versionnés
                │
           ┌────┴────┐
           ✅        ❌ → backend corrige
           │
           Merge → notification frontend
                │
                ▼
          Frontend pull → hook détecte changement de schema
          Frontend régénère ses types TS
          Frontend met à jour ses composants
          Frontend relance Vitest + Playwright
```

### Convention de commits

```bash
# Ajout non-breaking (nouveau champ optionnel dans le schema)
git commit -m "feat(api): add optional subtitle field to page schema"

# Changement breaking
git commit -m "feat(api)!: rename bodytext to body in content elements

BREAKING CHANGE: bodytext renommé en body dans content.schema.json.
Mettre à jour : composants TextElement, RichText, usages de meta.bodytext."
```

---

## 10. Pipeline CI/CD

### Principe de sécurité du CI

Le CI **ne dispose jamais de la base de production**. Il génère ses propres fixtures synthétiques à la volée via `generate_fixtures.sh`. Les snapshots sont générés en début de pipeline puis utilisés comme référence pour les tests.

```yaml
# .gitlab-ci.yml
stages:
  - prepare    # génération des fixtures + snapshots
  - test       # validation schemas + tests fonctionnels
  - e2e        # Playwright (optionnel)
  - security
  - notification
```

### Variables d'environnement GitLab (Settings > CI/CD > Variables)

| Variable | Valeur | Masquée |
|---|---|---|
| `SLACK_WEBHOOK_URL` | URL webhook | ✅ oui |
| `typo3DatabaseHost` | `mysql` | non |
| `typo3DatabaseName` | `typo3_test` | non |
| `typo3DatabaseUsername` | `root` | non |
| `typo3DatabasePassword` | `root` | ✅ oui |

### Artifacts entre stages

```yaml
# Stage prepare publie les fixtures et snapshots comme artifacts
prepare:fixtures:
  artifacts:
    paths:
      - Tests/Fixtures/Database/
      - Tests/Fixtures/Snapshots/
    expire_in: 1 hour  # jamais persistés longtemps
```

### Nettoyage automatique

```yaml
after_script:
  - rm -rf Tests/Fixtures/Database/
  - rm -rf Tests/Fixtures/Snapshots/
  - find . -name "*.csv" -path "*/Fixtures/*" -delete
```

---

## 11. Commandes de référence

### Backend

```bash
# === INSTALLATION (une seule fois) ===
composer require --dev typo3/testing-framework:"^8.0" justinrainbow/json-schema
chmod +x Tests/Scripts/*.sh
./Tests/Scripts/generate_schemas.sh
./Tests/Scripts/generate_headless_tests.sh

# === QUOTIDIEN ===
# Générer les fixtures locales (synthétiques)
./Tests/Scripts/generate_fixtures.sh

# Lancer les tests
vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless --testdox

# Régénérer les snapshots après un changement
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless

# Inspecter les diffs par zone
diff <(cat Tests/Fixtures/Snapshots/page_with_content.meta.json) <(echo "...")

# Vérifier avant commit
./Tests/Scripts/verify_snapshots.sh
git status  # s'assurer qu'aucun CSV ni snapshot n'est dans la staging area
```

### Frontend

```bash
# Générer les types TypeScript
npx json-schema-to-typescript ../Tests/Fixtures/Schemas/partials/*.schema.json -o src/types/api/

# Lancer les tests Vitest
npm run test

# Lancer les tests Playwright
cd playwright && npx playwright test

# Valider l'API légèrement
./front/scripts/validate-api.sh http://localhost:8080
```

### CI

```bash
# Générer les fixtures synthétiques (dans le pipeline)
./Tests/Scripts/generate_fixtures.sh

# Générer les snapshots (dans le pipeline, stage prepare)
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# Lancer les tests (dans le pipeline, stage test)
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless \
  --log-junit typo3temp/var/tests/headless.xml
```

---

## 12. FAQ et résolution de problèmes

**Q : Un développeur rejoint l'équipe, comment configure-t-il son environnement ?**

```bash
git clone <repo>
composer install
chmod +x Tests/Scripts/*.sh
./Tests/Scripts/generate_fixtures.sh   # génère les CSV locaux
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit  # génère les snapshots locaux
vendor/bin/phpunit                     # vérification
```

**Q : Le CI échoue sur "fichier snapshot introuvable"**

Le stage `prepare` n'a pas publié ses artifacts correctement. Vérifier la configuration `artifacts.paths` dans le job `prepare:fixtures`.

**Q : Un développeur a accidentellement commité un fichier CSV**

```bash
git rm --cached Tests/Fixtures/Database/page_with_content/pages.csv
echo "Tests/Fixtures/Database/" >> .gitignore
git add .gitignore
git commit -m "fix: remove sensitive fixture from git history"
# Si le fichier contient des données réelles, utiliser git-filter-repo pour purger l'historique
```

**Q : Comment partager un snapshot problématique avec un collègue ?**

Ne jamais le partager via Git. Utiliser un canal chiffré (Signal, partage sécurisé) ou le publier en artifact CI éphémère (expire_in: 1 hour).

**Q : Le test i18n échoue uniquement en CI**

La locale système (`fr_FR.UTF-8`) n'est pas installée dans l'image Docker. Ajouter dans le CI :
```yaml
before_script:
  - locale-gen fr_FR.UTF-8
  - update-locale LANG=fr_FR.UTF-8
```

**Q : Comment ajouter un 5ème scénario de test ?**

1. Ajouter le scénario dans `generate_fixtures.sh` (données synthétiques)
2. Créer `Tests/Fixtures/Schemas/page_with_xxx.schema.json` (versionné)
3. Ajouter le scénario dans `generate_headless_tests.sh` et relancer
4. Localement : `./Tests/Scripts/generate_fixtures.sh` + `UPDATE_SNAPSHOTS=1 vendor/bin/phpunit`
5. Commiter uniquement : `Tests/Scripts/`, `Tests/Fixtures/Schemas/`, `Tests/Functional/`

---

*Dernière mise à jour : février 2026 — TYPO3 v13 / EXT:headless v4 / PHP 8.2*
