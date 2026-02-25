# Stratégie de validation JSON — TYPO3 Headless

> Documentation à destination des équipes **backend** et **frontend** pour un projet TYPO3 v13 headless de type [pwa-demo](https://github.com/TYPO3-Headless/pwa-demo) (TYPO3 + Vue.js / Nuxt).

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture du projet](#2-architecture-du-projet)
3. [Les 4 piliers de la validation](#3-les-4-piliers-de-la-validation)
4. [Structure des fichiers de tests](#4-structure-des-fichiers-de-tests)
5. [Guide développeur Backend](#5-guide-développeur-backend)
6. [Guide développeur Frontend](#6-guide-développeur-frontend)
7. [Workflow Git collaboratif](#7-workflow-git-collaboratif)
8. [Pipeline CI/CD](#8-pipeline-cicd)
9. [Commandes de référence](#9-commandes-de-référence)
10. [FAQ et résolution de problèmes](#10-faq-et-résolution-de-problèmes)

---

## 1. Vue d'ensemble

Dans un projet TYPO3 headless comme le pwa-demo, le backend TYPO3 expose des **endpoints JSON** consommés par un frontend découplé (Vue.js / Nuxt). Le contrat entre les deux équipes est **ce JSON** : sa structure, ses types, ses champs.

Sans validation formelle, un changement backend peut silencieusement casser le frontend — et inversement, le frontend peut s'appuyer sur des champs qui n'ont jamais été garantis.

Cette stratégie répond à ce problème avec quatre mécanismes complémentaires :

```
Backend TYPO3 v13
      │
      │  /api/pages/2
      ▼
  Réponse JSON
      │
      ├── 1. JSON Schema     → valide la structure et les types
      ├── 2. Snapshot        → détecte toute régression
      ├── 3. FunctionalTest  → exécute dans un environnement isolé
      └── 4. CI/CD           → bloque la merge request si échec
                                        │
                                        ▼
                              Frontend Vue.js / Nuxt
                              (consomme le JSON en confiance)
```

---

## 2. Architecture du projet

Le projet pwa-demo est composé de deux parties distinctes :

```
pwa-demo/
├── config/         → configuration TYPO3 (sites, extensions)
├── data/           → base de données et fichiers uploadés
├── front/          → application Vue.js / Nuxt (frontend découplé)
│   ├── components/
│   ├── pages/
│   └── composables/
└── packages/       → extensions TYPO3 custom (backend)
    └── site_package/
```

Le backend TYPO3 avec `EXT:headless` transforme les pages et contenus en JSON. Le frontend Nuxt consomme ces endpoints via `useFetch` ou `useHeadlessData`. **Le JSON est le seul point de contact entre les deux équipes.**

---

## 3. Les 4 piliers de la validation

### Pilier 1 — Les fixtures CSV

Les fixtures sont des jeux de données minimaux versionnés qui alimentent la base de données de test. Ils remplacent un dump complet de la base de production.

**Règles impératives :**
- UIDs fixes et petits (1, 2, 3, 4...) pour la reproductibilité
- Aucun champ dynamique : pas de `crdate`, `tstamp`, `lastUpdated`
- Un dossier par scénario de page testé
- Maintenus **à la main** dans le dépôt Git — jamais générés depuis la base de production

Exemple (`Tests/Fixtures/Database/page_with_content/pages.csv`) :
```csv
uid,pid,title,slug,doktype,hidden,deleted
2,0,"Page With Content","/page-with-content",1,0,0
```

Exemple (`Tests/Fixtures/Database/page_with_content/tt_content.csv`) :
```csv
uid,pid,header,bodytext,CType,colPos,sorting,hidden
10,2,"Introduction","Bienvenue sur notre page de test","text",0,1,0
11,2,"Notre Mission","Former les musiciens de demain","text",0,2,0
```

### Pilier 2 — Le JSON Schema

Le schema définit le **contrat formel** de l'API : quels champs sont obligatoires, quels types sont attendus, quelles valeurs sont acceptées. Il constitue la documentation vivante de l'API pour le frontend.

Exemple (`Tests/Fixtures/Schemas/page_with_content.schema.json`) :
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["id", "type", "title", "slug", "content"],
  "properties": {
    "id": { "type": "integer", "minimum": 1 },
    "type": { "type": "string", "enum": ["pages"] },
    "title": { "type": "string", "minLength": 1 },
    "slug": { "type": "string", "pattern": "^/[a-zA-Z0-9\\-/]+$" },
    "content": {
      "type": "object",
      "required": ["elements"],
      "properties": {
        "elements": {
          "type": "array",
          "minItems": 1
        }
      }
    }
  }
}
```

### Pilier 3 — Le Snapshot JSON

Le snapshot est une photographie de la réponse JSON de référence. Tout écart détecté lors d'un test est un signal : soit une **régression involontaire** (à corriger), soit un **changement volontaire** (à valider et commiter).

Exemple (`Tests/Fixtures/Snapshots/page_with_content.json`) :
```json
{
  "id": 2,
  "type": "pages",
  "title": "Page With Content",
  "slug": "/page-with-content",
  "content": {
    "elements": [
      {
        "id": 10,
        "type": "text",
        "content": { "header": "Introduction", "bodytext": "Bienvenue sur notre page de test" }
      }
    ]
  }
}
```

### Pilier 4 — Le FunctionalTestCase TYPO3

Le test PHPUnit orchestre les trois piliers précédents dans un environnement complètement isolé, sans serveur web, sans base de données de production.

```
setUp()                    → importe les CSV dans une DB SQLite temporaire
executeFrontendSubRequest  → appelle le frontend TYPO3 en interne (pas de curl)
assertJsonSchema           → valide contre le schema
assertJsonSnapshot         → compare avec le snapshot
tearDown()                 → détruit la DB temporaire
```

---

## 4. Structure des fichiers de tests

```
Tests/
├── Functional/
│   └── Headless/
│       ├── AbstractHeadlessTestCase.php    ← classe de base (API TYPO3 v13)
│       ├── PageSimpleTest.php
│       ├── PageWithContentTest.php
│       ├── PageWithImagesTest.php
│       └── PageWithCategoriesTest.php
│
├── Fixtures/
│   ├── Database/
│   │   ├── page_simple/
│   │   │   └── pages.csv
│   │   ├── page_with_content/
│   │   │   ├── pages.csv
│   │   │   └── tt_content.csv
│   │   ├── page_with_images/
│   │   │   ├── pages.csv
│   │   │   ├── tt_content.csv
│   │   │   ├── sys_file.csv
│   │   │   └── sys_file_reference.csv
│   │   └── page_with_categories/
│   │       ├── pages.csv
│   │       ├── tt_content.csv
│   │       ├── sys_category.csv
│   │       └── sys_category_record_mm.csv
│   │
│   ├── Schemas/
│   │   ├── partials/                        ← schemas partiels réutilisables
│   │   │   ├── meta.schema.json             (SEO : title, robots, canonical, og:*)
│   │   │   ├── i18n.schema.json             (langue, locale, hreflang, alternates)
│   │   │   ├── breadcrumbs.schema.json      (fil d'Ariane)
│   │   │   ├── appearance.schema.json       (layout, backendLayout)
│   │   │   └── content.schema.json          (colPos, éléments de contenu)
│   │   ├── page_simple.schema.json          ← schema principal ($ref vers partiels)
│   │   ├── page_with_content.schema.json
│   │   ├── page_with_images.schema.json
│   │   └── page_with_categories.schema.json
│   │
│   └── Snapshots/
│       ├── page_simple.json                 ← snapshot global
│       ├── page_simple.meta.json            ← snapshot partiel zone meta
│       ├── page_simple.i18n.json            ← snapshot partiel zone i18n
│       ├── page_simple.breadcrumbs.json
│       ├── page_simple.appearance.json
│       ├── page_simple.content.json
│       ├── page_with_content.json
│       ├── page_with_content.meta.json
│       ├── page_with_content.i18n.json
│       ├── page_with_content.breadcrumbs.json
│       ├── page_with_content.appearance.json
│       └── page_with_content.content.json
│       └── ... (idem pour les autres scénarios)
│
└── Scripts/
    ├── generate_headless_tests.sh   ← génère les fichiers PHP de test
    ├── generate_schemas.sh          ← génère les schemas partiels (nouveau)
    ├── update_snapshots.sh          ← régénère les snapshots via PHPUnit
    └── verify_snapshots.sh          ← vérifie la validité des snapshots
```

---

## 5. Guide développeur Backend

Le développeur backend TYPO3 est responsable de :
- la création et la mise à jour des **fixtures CSV**
- la définition et l'évolution du **JSON Schema**
- la mise à jour des **snapshots** après tout changement intentionnel

### Installation initiale

```bash
# 1. Installer les dépendances PHP de test
composer require --dev typo3/testing-framework justinrainbow/json-schema

# 2. Générer les schemas partiels (meta, i18n, breadcrumbs, appearance, content)
chmod +x Tests/Scripts/*.sh
./Tests/Scripts/generate_schemas.sh

# 3. Générer la structure des tests et les fichiers PHP
./Tests/Scripts/generate_headless_tests.sh

# 4. Remplir les CSV dans Tests/Fixtures/Database/ (à la main)
# Voir les exemples dans Tests/Fixtures/Database/page_with_content/

# 5. Générer tous les snapshots (global + partiels par zone)
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# 6. Commiter tout
git add Tests/
git commit -m "feat: add headless JSON validation tests"
```

### Ajouter un nouveau type de contenu

Exemple : on ajoute un CType `accordion` à TYPO3.

**Étape 1** — Créer ou compléter le CSV fixture

```csv
# Tests/Fixtures/Database/page_with_accordion/tt_content.csv
uid,pid,header,bodytext,CType,colPos,sorting,hidden
20,5,"FAQ","Contenu accordéon","accordion",0,1,0
```

**Étape 2** — Mettre à jour le JSON Schema pour accepter le nouveau type

```json
"type": {
  "type": "string",
  "enum": ["text", "image", "accordion"]
}
```

**Étape 3** — Régénérer le snapshot après que le code TYPO3 est en place

```bash
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless/PageWithAccordionTest.php
```

**Étape 4** — Vérifier que le snapshot généré est correct, commiter

```bash
git diff Tests/Fixtures/Snapshots/      # inspecter le diff
git add Tests/Fixtures/Snapshots/ Tests/Fixtures/Schemas/ Tests/Fixtures/Database/
git commit -m "feat: add accordion content type"
```

### Modifier un champ existant

Exemple : on renomme `bodytext` en `body` dans la réponse JSON.

```bash
# Modifier le code TYPO3 / DataProcessor...

# Régénérer le snapshot
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...

# Vérifier le diff — le frontend DOIT être informé de ce changement
git diff Tests/Fixtures/Snapshots/

# Commiter avec un message explicite
git commit -m "breaking: rename bodytext to body in headless response

BREAKING CHANGE: le champ bodytext est renommé en body dans tous
les éléments de contenu. Le frontend doit mettre à jour ses composants."
```

> ⚠️ **Tout changement de snapshot est un signal pour le frontend.** Utiliser des commits explicites avec `BREAKING CHANGE:` dans le message.

### Lancer les tests unitaires localement

```bash
# Lancer tous les tests headless
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless \
  --testdox

# Lancer un seul test
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless/PageWithContentTest.php

# Vérifier les snapshots sans lancer PHPUnit
./Tests/Scripts/verify_snapshots.sh
```

---

## 6. Guide développeur Frontend

Le développeur frontend Vue.js / Nuxt est **consommateur** du JSON. Il n'écrit pas de tests PHPUnit, mais il utilise les artefacts produits par le backend pour typer et sécuriser son code.

### Utiliser les JSON Schemas pour typer les composants

Les fichiers `Tests/Fixtures/Schemas/*.schema.json` peuvent être convertis en types TypeScript avec l'outil `json-schema-to-typescript`.

```bash
# Dans le dossier front/
npm install -D json-schema-to-typescript

# Générer les types depuis les schemas du backend
npx json-schema-to-typescript \
  ../../Tests/Fixtures/Schemas/page_with_content.schema.json \
  -o src/types/PageWithContent.ts
```

Le fichier généré donne un type TypeScript utilisable dans les composants Nuxt :

```typescript
// src/types/PageWithContent.ts (généré automatiquement)
export interface PageWithContent {
  id: number;
  type: "pages";
  title: string;
  slug: string;
  content: {
    elements: ContentElement[];
  };
}
```

```vue
<!-- components/PageContent.vue -->
<script setup lang="ts">
import type { PageWithContent } from '~/types/PageWithContent'

const { data } = await useFetch<PageWithContent>('/api/pages/2')
// TypeScript connaît maintenant la structure exacte de data
</script>
```

### Utiliser les Snapshots comme données de mock

Les fichiers `Tests/Fixtures/Snapshots/*.json` sont des réponses réelles de l'API. Ils peuvent servir de **mocks pour les tests Vitest / Cypress** du frontend.

```typescript
// tests/unit/PageContent.test.ts
import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import PageContent from '~/components/PageContent.vue'

// Import du snapshot généré par le backend
import pageSnapshot from '../../../../Tests/Fixtures/Snapshots/page_with_content.json'

describe('PageContent', () => {
  it('affiche le titre de la page', () => {
    const wrapper = mount(PageContent, {
      props: { page: pageSnapshot }
    })
    expect(wrapper.text()).toContain('Page With Content')
  })

  it('affiche tous les éléments de contenu', () => {
    const wrapper = mount(PageContent, {
      props: { page: pageSnapshot }
    })
    const elements = wrapper.findAll('[data-testid="content-element"]')
    expect(elements).toHaveLength(pageSnapshot.content.elements.length)
  })
})
```

### Surveiller les changements de snapshot

Configurer une alerte Git pour être notifié de tout changement dans les snapshots :

```bash
# Dans front/, ajouter un hook post-merge
cat > ../.git/hooks/post-merge << 'EOF'
#!/bin/bash
changed=$(git diff HEAD@{1} HEAD --name-only | grep "Tests/Fixtures/Snapshots/")
if [ -n "$changed" ]; then
  echo ""
  echo "⚠️  ATTENTION : Des snapshots JSON ont été modifiés !"
  echo "   Fichiers impactés :"
  echo "$changed" | sed 's/^/   - /'
  echo ""
  echo "   Vérifiez si vos composants Vue.js doivent être mis à jour."
  echo ""
fi
EOF
chmod +x ../.git/hooks/post-merge
```

### Workflow frontend lors d'un changement de contrat

Quand le backend notifie d'un changement (commit avec `BREAKING CHANGE:`) :

```bash
# 1. Récupérer les changements
git pull origin main

# 2. Le hook post-merge affiche les snapshots modifiés
# 3. Inspecter le diff des snapshots
git diff HEAD@{1} HEAD -- Tests/Fixtures/Snapshots/

# 4. Régénérer les types TypeScript
npx json-schema-to-typescript Tests/Fixtures/Schemas/*.schema.json -o front/src/types/

# 5. Mettre à jour les composants en erreur TypeScript
# 6. Relancer les tests frontend
cd front && npm run test
```

---

## 7. Workflow Git collaboratif

### Branches et responsabilités

```
main ─────────────────────────────────────────────────────────►
      │                              │
      └─ feature/backend-accordion   └─ feature/frontend-accordion
         (développeur backend)          (développeur frontend)
         
         1. Modifie TYPO3              1. Attend le merge backend
         2. Met à jour CSV/Schema      2. Pull main
         3. Régénère snapshots         3. Régénère les types TS
         4. Ouvre MR → CI bloque/passe 4. Met à jour les composants
         5. Merge si CI ✅             5. Ouvre MR frontend
```

### Cycle de vie d'un changement de contrat JSON

```
Backend ouvre une MR
        │
        ▼
CI vérifie les snapshots (verify_snapshots.sh)
        │
        ▼
CI lance les FunctionalTests
        │
   ┌────┴────┐
   │         │
   ✅        ❌
   │         │
   Merge     Le développeur backend corrige
   │         ou met à jour le snapshot avec
   │         UPDATE_SNAPSHOTS=1 si changement volontaire
   │
   ▼
Frontend reçoit la notif (hook / Slack CI)
        │
        ▼
Frontend met à jour ses types et composants
        │
        ▼
Frontend ouvre sa propre MR avec les adaptations
```

### Convention de commits pour les changements de contrat

```bash
# Ajout non-breaking (nouveau champ optionnel)
git commit -m "feat(api): add optional 'subtitle' field to page response"

# Changement breaking (renommage, suppression, type change)
git commit -m "feat(api)!: rename bodytext to body in content elements

BREAKING CHANGE: le champ bodytext est renommé en body.
Frontend concerné : composants TextElement, RichText.
Snapshot mis à jour : page_with_content.json, page_with_images.json"
```

---

## 8. Pipeline CI/CD

Le pipeline GitLab bloque automatiquement toute merge request si :
- un snapshot ne correspond plus à la réponse réelle de l'API
- la réponse ne respecte plus le JSON Schema
- un test PHPUnit échoue

### Étapes du pipeline

```yaml
stages:
  - test        # vérification snapshots + tests fonctionnels
  - security    # audit des dépendances
  - notification # Slack
```

**Stage `verify_snapshots`** (rapide, ~10s)
Vérifie que les snapshots sont du JSON valide, sans UID instables, sans champs dynamiques. S'exécute avant les tests lourds pour un feedback rapide.

**Stage `test:headless`** (plus lent, ~2-3min)
Lance l'environnement TYPO3 complet avec MySQL 8.0, importe les fixtures, exécute tous les FunctionalTests.

**Variables d'environnement requises dans GitLab CI/CD Settings :**

| Variable | Description |
|---|---|
| `SLACK_WEBHOOK_URL` | URL du webhook Slack pour les notifications |
| `typo3DatabaseHost` | `mysql` (nom du service dans le pipeline) |
| `typo3DatabaseName` | `typo3_test` |
| `typo3DatabaseUsername` | `root` |
| `typo3DatabasePassword` | `root` |

### Bloquer une MR sur snapshot modifié non commité

Si un développeur oublie de commiter les snapshots mis à jour, le CI échouera avec un message explicite :

```
FAIL  Tests/Functional/Headless/PageWithContentTest.php
✗ jsonResponseMatchesSnapshot
  Failed asserting that two JSON strings are equal.
  --- Expected (snapshot)
  +++ Actual (response)
  @@ -5,7 +5,8 @@
       "bodytext": "Bienvenue"
  +    "subtitle": "Nouveau sous-titre"
```

---

## 9. Commandes de référence

### Backend

```bash
# Générer les schemas partiels (première fois ou après modification)
./Tests/Scripts/generate_schemas.sh

# Générer la structure des tests (première fois)
./Tests/Scripts/generate_headless_tests.sh

# Lancer tous les tests headless
vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless \
  --testdox

# Régénérer tous les snapshots (global + partiels) après un changement volontaire
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
  -c typo3/sysext/core/Build/FunctionalTests.xml \
  Tests/Functional/Headless

# Inspecter le diff par zone après régénération
git diff Tests/Fixtures/Snapshots/*.meta.json        # changements SEO
git diff Tests/Fixtures/Snapshots/*.i18n.json        # changements i18n
git diff Tests/Fixtures/Snapshots/*.breadcrumbs.json # changements navigation
git diff Tests/Fixtures/Snapshots/*.content.json     # changements contenu

# Vérifier les snapshots avant un commit
./Tests/Scripts/verify_snapshots.sh
```

### Frontend

```bash
# Générer les types TypeScript depuis les schemas
npx json-schema-to-typescript \
  Tests/Fixtures/Schemas/*.schema.json \
  -o front/src/types/

# Lancer les tests Vitest avec les mocks snapshot
cd front && npm run test

# Inspecter un changement de contrat après un git pull
git diff HEAD@{1} HEAD -- Tests/Fixtures/Snapshots/
```

---

## 10. FAQ et résolution de problèmes

**Q : Le test échoue avec "Class InternalRequest not found"**

La dépendance `typo3/testing-framework` n'est pas installée ou est trop ancienne. Vérifier :
```bash
composer require --dev typo3/testing-framework:"^8.0"
```

**Q : Le snapshot est vide après `UPDATE_SNAPSHOTS=1`**

L'endpoint ne répond pas correctement. Vérifier que l'extension headless est dans `testExtensionsToLoad` et que la configuration de site (`config/sites/`) est accessible dans le contexte de test.

**Q : Les UIDs dans le snapshot sont différents à chaque run**

Des champs comme `uid` ou `pid` proviennent de tables non fixturées. S'assurer que toutes les tables nécessaires ont un CSV dans `Tests/Fixtures/Database/[scenario]/`.

**Q : Le frontend veut tester un nouveau champ avant que le backend ne soit prêt**

Utiliser le snapshot existant comme mock et ajouter manuellement le nouveau champ dans une copie locale. Ne pas commiter de snapshot modifié manuellement — attendre la MR backend correspondante.

**Q : `verify_snapshots.sh` signale des "champs dynamiques détectés"**

Un snapshot contient un champ `crdate`, `tstamp` ou `lastUpdated`. Ces valeurs changent à chaque run et rendent le snapshot instable. Ajouter ces champs à la liste d'exclusion dans le DataProcessor TYPO3, ou les filtrer dans le test avant la comparaison.

**Q : Comment ajouter un 5ème scénario de test ?**

1. Créer le dossier `Tests/Fixtures/Database/page_with_xxx/` avec les CSV
2. Créer le schema `Tests/Fixtures/Schemas/page_with_xxx.schema.json`
3. Ajouter le scénario dans `generate_headless_tests.sh` et relancer le script
4. Générer le snapshot avec `UPDATE_SNAPSHOTS=1`
5. Commiter l'ensemble

---

*Dernière mise à jour : février 2026 — TYPO3 v13 / EXT:headless v4 / PHP 8.2*
