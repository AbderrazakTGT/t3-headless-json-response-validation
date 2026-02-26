# Stratégie de validation JSON — TYPO3 Headless v13

> Documentation pour les équipes **backend** et **frontend** d'un projet TYPO3 v13 headless
> de type [pwa-demo](https://github.com/TYPO3-Headless/pwa-demo) (TYPO3 + Vue.js / Nuxt).

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Contraintes et décisions](#2-contraintes-et-décisions)
3. [Les 4 piliers de la validation](#3-les-4-piliers-de-la-validation)
4. [Structure des fichiers](#4-structure-des-fichiers)
5. [Guide développeur Backend](#5-guide-développeur-backend)
6. [Guide développeur Frontend](#6-guide-développeur-frontend)
7. [Intégration Playwright](#7-intégration-playwright)
8. [Workflow Git collaboratif](#8-workflow-git-collaboratif)
9. [Pipeline CI/CD](#9-pipeline-cicd)
10. [Commandes de référence](#11-commandes-de-référence)
11. [FAQ](#12-faq)

---

## 1. Vue d'ensemble

Le backend TYPO3 v13 avec EXT:headless expose des pages complètes en JSON. Chaque réponse contient plusieurs zones : `meta` (SEO), `i18n` (langues), `breadcrumbs`, `appearance` (layout), `content` (colPos). Le frontend Nuxt consomme ces endpoints — **le JSON est le seul contrat entre les deux équipes**.

```
Base de production (1,3 Go — DONNÉES SENSIBLES RGPD)
      │
      │  cleanup_database.sh     extract_and_anonymize.sh
      │  (soft-deletes TYPO3)    (anonymisation + fe_users test)
      ▼
Fixtures CSV (~50 Ko/scénario)   JSON Schemas partiels
✅ VERSIONNÉES dans Git           ✅ VERSIONNÉS dans Git
(après anonymisation)             (structure, pas de données)
      │                                │
      ▼                                ▼
FunctionalTestCase TYPO3 ────────► Validation
(versionné, sans données)         7 méthodes/scénario
      │
      ▼
Snapshots JSON                   CI/CD GitLab
❌ gitignorés                     (génère fixtures à la volée
(générés localement)              si pas de DB prod disponible)
```

### Décision clé : les fixtures sont versionnées dans Git

Contrairement aux snapshots, les fixtures CSV sont **versionnées** car :
- Taille : **30–50 Ko par scénario** (vs 1,3 Go en production)
- Permettent le **travail hors-ligne** (TGV, avion)
- Reproductibles sans connexion à la base
- Accélèrent le CI (pas de download, pas de DDEV requis)

---

## 2. Contraintes et décisions

| Contrainte | Solution retenue |
|---|---|
| Base 1,3 Go | Extraction de 50 Ko représentatifs par scénario |
| Données sensibles RGPD | Anonymisation via `extract_and_anonymize.sh` avant commit |
| Soft-deletes TYPO3 | `cleanup_database.sh` + `deleted=0` dans toutes les requêtes |
| FE users protégés | 3 comptes de test (standard, premium, admin) — même mot de passe |
| Travail hors-ligne | Fixtures versionnées dans Git → `git clone` suffit |
| Tests reproductibles | UIDs stables 1–10, pas de crdate/tstamp |
| CI sans base prod | `generate_fixtures.sh` synthétique ou fixtures Git |
| Performance | Tests isolés via InternalRequest — pas de serveur HTTP |

### Ce qui est versionné dans Git

| Fichier | Versionné | Pourquoi |
|---|---|---|
| `Tests/Scripts/*.sh` | ✅ | scripts sans données |
| `Tests/Fixtures/Schemas/**` | ✅ | contrat API (structure uniquement) |
| `Tests/Functional/**/*.php` | ✅ | code sans données |
| `Tests/Fixtures/Database/**/*.csv` | ✅ | **anonymisées, ~50 Ko** |
| `Tests/Fixtures/Snapshots/**/*.json` | ❌ | peuvent contenir des titres/slugs réels |
| `.gitignore`, `.gitlab-ci.yml` | ✅ | infrastructure |

---

## 3. Les 4 piliers de la validation

### Pilier 1 — Fixtures CSV (~50 Ko, versionnées après anonymisation)

Jeux de données minimaux représentatifs. **5 scénarios** :

| Scénario | Tables | Cas couverts |
|---|---|---|
| `page_simple` | pages | Page publique basique |
| `page_with_content` | pages, tt_content | Contenu texte multi-éléments |
| `page_with_images` | pages, tt_content, sys_file, sys_file_reference | Images FAL |
| `page_with_categories` | pages, tt_content, sys_category, sys_category_record_mm | Catégories |
| `page_protected` | pages, tt_content, fe_users, fe_groups | Authentification FE |

**Règles impératives :**
- UIDs stables : 1–10 (pages), 10–40 (tt_content), 100–102 (fe_users)
- `deleted=0`, `hidden=0` dans toutes les lignes
- Aucun champ dynamique : `crdate=0`, `tstamp=0`
- FE users : même mot de passe `password` pour tous (hash bcrypt TYPO3)
- Aucune donnée réelle : noms/emails/téléphones anonymisés

**Deux modes de génération :**

```
Mode A — Synthétique (CI, développeurs sans DB prod)
  ./Tests/Scripts/generate_fixtures.sh
  → Données fictives mais structurellement correctes

Mode B — Extraction + anonymisation (développeurs avec DDEV)
  ./Tests/Scripts/cleanup_database.sh     ← purge soft-deletes
  ./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200
  → Données extraites de la vraie base, anonymisées
  git add Tests/Fixtures/Database/        ← commit après vérification
```

### Pilier 2 — JSON Schemas partiels (versionnés)

Un schema par zone de réponse, référencés via `$ref` depuis le schema principal. Aucune donnée, uniquement la structure.

```
Tests/Fixtures/Schemas/
├── partials/
│   ├── meta.schema.json        → SEO (title, robots, canonical, og:*)
│   ├── i18n.schema.json        → langue, locale, hreflang, alternates
│   ├── breadcrumbs.schema.json → fil d'Ariane
│   ├── appearance.schema.json  → layout, backendLayout
│   └── content.schema.json     → colPos + éléments de contenu
└── page_with_content.schema.json → $ref vers partiels
```

### Pilier 3 — Snapshots JSON (gitignorés, générés localement)

Photographies de la réponse réelle, utilisées pour détecter toute régression. Un snapshot global + un snapshot partiel par zone pour des diffs Git lisibles.

```
Tests/Fixtures/Snapshots/          ← gitignored
├── page_with_content.json         ← snapshot global
├── page_with_content.meta.json    ← zone SEO
├── page_with_content.i18n.json    ← zone i18n
├── page_with_content.breadcrumbs.json
├── page_with_content.appearance.json
└── page_with_content.content.json
```

**Partage des snapshots entre développeurs** (sans Git) : en CI, ils sont publiés en artifacts éphémères (`expire_in: 1 hour`). En local, chaque développeur les génère avec `UPDATE_SNAPSHOTS=1`.

### Pilier 4 — FunctionalTestCase TYPO3 v13

7 méthodes de test par scénario, basées sur `AbstractHeadlessTestCase` :

```
jsonResponseMatchesGlobalSchema()         → schema principal
jsonResponseMatchesGlobalSnapshot()       → snapshot global
metaZoneMatchesSchemaAndSnapshot()        → schema partiel + snapshot + règles métier
i18nZoneMatchesSchemaAndSnapshot()        → locale, hreflang, alternates
breadcrumbsZoneMatchesSchemaAndSnapshot() → racine=/, current=true, dernier=current
appearanceZoneMatchesSchemaAndSnapshot()  → layout, backendLayout
contentZoneMatchesSchemaAndSnapshot()     → colPos présents, types corrects
```

Pour le scénario `page_protected`, des méthodes supplémentaires valident l'authentification FE :

```
testUnauthenticatedAccessIsDenied()       → HTTP 403 sans cookie
testAuthenticatedStandardUserCanAccess()  → accès avec fe_users uid=100
testPremiumUserSeesAdditionalContent()    → contenu supplémentaire uid=101
```

---

## 4. Structure des fichiers

```
Tests/
├── Functional/
│   └── Headless/
│       ├── AbstractHeadlessTestCase.php    ✅ versionné
│       ├── PageSimpleTest.php              ✅ versionné
│       ├── PageWithContentTest.php         ✅ versionné
│       ├── PageWithImagesTest.php          ✅ versionné
│       ├── PageWithCategoriesTest.php      ✅ versionné
│       └── PageProtectedTest.php          ✅ versionné
│
├── Fixtures/
│   ├── Database/                           ✅ VERSIONNÉ (anonymisé, ~50 Ko)
│   │   ├── shared/
│   │   │   ├── fe_groups.csv              3 groupes (standard, premium, admin)
│   │   │   └── fe_users.csv               3 utilisateurs — mdp: password
│   │   ├── page_simple/pages.csv
│   │   ├── page_with_content/{pages,tt_content}.csv
│   │   ├── page_with_images/{pages,tt_content,sys_file,sys_file_reference}.csv
│   │   ├── page_with_categories/{pages,tt_content,sys_category,sys_category_record_mm}.csv
│   │   └── page_protected/{pages,tt_content,fe_groups,fe_users}.csv
│   │
│   ├── Schemas/                            ✅ VERSIONNÉ
│   │   ├── partials/{meta,i18n,breadcrumbs,appearance,content}.schema.json
│   │   └── page_{simple,with_content,with_images,with_categories,protected}.schema.json
│   │
│   └── Snapshots/                          ❌ gitignored — générés localement
│       ├── page_with_content.json
│       ├── page_with_content.meta.json
│       └── ... (un global + 5 partiels par scénario)
│
└── Scripts/                                ✅ VERSIONNÉ
    ├── cleanup_database.sh         NOUVEAU — purge soft-deletes TYPO3
    ├── extract_and_anonymize.sh    extrait + anonymise depuis DDEV
    ├── generate_fixtures.sh        génère des données synthétiques (CI/hors-ligne)
    ├── generate_schemas.sh         génère les schemas partiels
    ├── generate_headless_tests.sh  génère les fichiers PHP de test
    ├── update_snapshots.sh         régénère les snapshots via PHPUnit
    └── verify_snapshots.sh         vérifie l'intégrité des snapshots
```

---

## 5. Guide développeur Backend

### Installation initiale (une seule fois)

```bash
# 1. Dépendances
composer require --dev typo3/testing-framework:"^8.0" justinrainbow/json-schema

# 2. Générer les schemas et les fichiers PHP de test
chmod +x Tests/Scripts/*.sh
./Tests/Scripts/generate_schemas.sh
./Tests/Scripts/generate_headless_tests.sh

# 3a. Vous avez DDEV avec la base locale : extraction + anonymisation
./Tests/Scripts/cleanup_database.sh          # purge soft-deletes
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200

# 3b. Sans base locale (CI, hors-ligne) : données synthétiques
./Tests/Scripts/generate_fixtures.sh

# 4. Générer les snapshots
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# 5. Vérifier
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless --testdox

# 6. Commiter (fixtures CSV incluses — anonymisées)
git add Tests/Fixtures/Database/ Tests/Fixtures/Schemas/ Tests/Functional/ Tests/Scripts/
git status  # vérifier qu'aucun snapshot n'est stagé
git commit -m "feat: add headless JSON validation tests with anonymized fixtures"
```

### Workflow quotidien

```bash
# Lancer les tests
vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless --testdox

# Après un changement TYPO3 volontaire
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...
# git diff Tests/Fixtures/Snapshots/  ← diffs locaux uniquement

# Après un changement de structure (nouveau champ)
# 1. Mettre à jour le schema partiel concerné
# 2. UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...
# 3. git add Tests/Fixtures/Schemas/ && git commit -m "feat(api): ..."
```

### Gestion des soft-deletes avant extraction

```bash
# Vérifier combien d'enregistrements deleted=1 existent
ddev mysql -e "SELECT table_name, COUNT(*) FROM information_schema.tables t
  JOIN (SELECT 'pages' t UNION SELECT 'tt_content' UNION SELECT 'sys_category') n
  ON t.table_name = n.t WHERE t.table_schema = DATABASE()" --batch

# Mode simulation (dry-run)
./Tests/Scripts/cleanup_database.sh --dry-run

# Purge réelle (base DDEV locale uniquement)
./Tests/Scripts/cleanup_database.sh --min-age=30

# Re-extraire après nettoyage
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200
```

### Gestion des FE users

Les 3 utilisateurs de test sont définis dans `Tests/Fixtures/Database/shared/fe_users.csv` :

| UID | Username | Groupes | Cas testé |
|---|---|---|---|
| 100 | `test_standard` | groupe 1 | accès standard |
| 101 | `test_premium` | groupes 1+2 | accès premium |
| 102 | `test_admin` | groupes 1+2+3 | accès admin complet |

Mot de passe : **`password`** (hash bcrypt TYPO3 dans le CSV).

---

## 6. Guide développeur Frontend

### Génération des types TypeScript

```bash
npm install -D json-schema-to-typescript

# Les schemas sont versionnés — disponibles sans connexion
npx json-schema-to-typescript \
  Tests/Fixtures/Schemas/partials/*.schema.json \
  -o front/src/types/api/
```

### Utiliser les snapshots comme mocks Vitest

```typescript
// front/tests/unit/PageContent.test.ts
import pageSnapshot from '../../../Tests/Fixtures/Snapshots/page_with_content.json'

describe('PageContent', () => {
  it('affiche le titre', () => {
    const wrapper = mount(PageContent, { props: { page: pageSnapshot } })
    expect(wrapper.text()).toContain(pageSnapshot.title)
  })
})
```

> Note : les snapshots sont gitignorés. En CI, ils viennent des artifacts du stage `prepare`.
> En local, les générer avec `UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...`.

### Validation légère de l'API (sans PHPUnit)

```bash
./front/scripts/validate-api.sh http://localhost:8080
```

---

## 7. Intégration Playwright

```typescript
// playwright/tests/headless-json.spec.ts
import snapshot from '../../Tests/Fixtures/Snapshots/page_with_content.json'

test('titre SEO correct', async ({ page }) => {
  await page.goto(snapshot.slug)
  await expect(page).toHaveTitle(new RegExp(snapshot.meta.title))
})

test('fe_user standard peut accéder à la page protégée', async ({ page }) => {
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

```
Backend modifie TYPO3
  ├── Si nouvelle structure    → met à jour Tests/Fixtures/Schemas/ (commit)
  ├── Si nouvelles données     → re-extrait + anonymise + commit Tests/Fixtures/Database/
  ├── Génère snapshots locaux  → UPDATE_SNAPSHOTS=1 vendor/bin/phpunit (pas de commit)
  └── Push → CI vérifie

Frontend reçoit le push
  ├── Hook post-merge détecte changement de schemas
  ├── Régénère types TS : npx json-schema-to-typescript ...
  └── Met à jour composants + tests Vitest

CI
  ├── prepare : generate_fixtures.sh + UPDATE_SNAPSHOTS=1 (artifacts éphémères)
  ├── test    : phpunit (consomme les artifacts)
  └── cleanup : rm -rf Snapshots/ après tests
```

### Convention de commits

```bash
# Changement non-breaking (nouveau champ optionnel)
git commit -m "feat(api): add optional subtitle field to page schema"

# Changement breaking (renommage, suppression)
git commit -m "feat(api)!: rename bodytext to body in content elements

BREAKING CHANGE: bodytext → body dans content.schema.json.
Frontend : mettre à jour composants TextElement, RichText."

# Mise à jour des fixtures (re-extraction)
git commit -m "fix(fixtures): update anonymized CSV after schema change"
```

---

## 9. Pipeline CI/CD

Le CI ne dispose jamais de la base de production. Il génère ses propres fixtures synthétiques via `generate_fixtures.sh`. Les snapshots sont des artifacts éphémères (`expire_in: 1 hour`).

```yaml
stages:
  - prepare    # generate_fixtures.sh + UPDATE_SNAPSHOTS=1
  - test       # phpunit + verify_snapshots.sh
  - e2e        # Playwright (optionnel)
  - security
  - notification
```

**Variables GitLab requises** :

| Variable | Valeur | Masquée |
|---|---|---|
| `SLACK_WEBHOOK_URL` | URL webhook | ✅ |
| `typo3DatabasePassword` | `root` | ✅ |

---

## 10. Commandes de référence

### Backend

```bash
# Nettoyage soft-deletes (avant extraction)
./Tests/Scripts/cleanup_database.sh --dry-run
./Tests/Scripts/cleanup_database.sh --min-age=30

# Extraction + anonymisation depuis DDEV
./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200

# Ou génération synthétique (sans DDEV)
./Tests/Scripts/generate_fixtures.sh

# Tests
vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless --testdox

# Régénérer snapshots
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless

# Vérifier avant commit
./Tests/Scripts/verify_snapshots.sh
git status  # vérifier qu'aucun snapshot n'est stagé
```

### Commandes TYPO3 natives (cleanup)

```bash
# Purge des enregistrements soft-deleted (>30 jours)
ddev exec vendor/bin/typo3 cleanup:deletedrecords --min-age=30

# Nettoyage des relations orphelines
ddev exec vendor/bin/typo3 cleanup:missingrelations --update-refindex

# Mise à jour de l'index de référence
ddev exec vendor/bin/typo3 referenceindex:update
```

---

## 11. FAQ

**Q : Nouveau développeur — comment démarrer ?**
```bash
git clone <repo> && composer install
chmod +x Tests/Scripts/*.sh
# Avec DDEV : ./Tests/Scripts/cleanup_database.sh && ./Tests/Scripts/extract_and_anonymize.sh
# Sans DDEV : ./Tests/Scripts/generate_fixtures.sh
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless
vendor/bin/phpunit ...
```

**Q : Je travaille dans le TGV sans connexion — comment lancer les tests ?**
Les fixtures CSV sont versionnées dans Git. Après `git clone`, seuls les snapshots doivent être générés localement (`UPDATE_SNAPSHOTS=1 vendor/bin/phpunit`). Aucune connexion réseau requise.

**Q : Le CI échoue sur "soft-delete records found"**
Le CI utilise `generate_fixtures.sh` qui génère des données synthétiques propres (`deleted=0` partout). Ce message ne devrait pas apparaître en CI. En local, lancez `cleanup_database.sh`.

**Q : La page protégée retourne 403 même avec fe_user**
Vérifier que `fe_users.csv` et `fe_groups.csv` sont bien importés et que le `usergroup` de la page (champ `fe_group`) correspond à l'UID du groupe de l'utilisateur de test.

**Q : Un développeur a accidentellement commité un snapshot**
```bash
git rm --cached Tests/Fixtures/Snapshots/page_with_content.json
git commit -m "fix: remove snapshot from git"
# Si données sensibles dans le snapshot : git-filter-repo pour purger l'historique
```

**Q : Les UIDs dans les snapshots changent entre les runs**
Des tables ne sont pas fixturées. Vérifier que toutes les tables référencées dans les CSV existent dans le scénario (pages.csv, tt_content.csv, etc.).

---

*Dernière mise à jour : février 2026 — TYPO3 v13 / EXT:headless v4 / PHP 8.2*
