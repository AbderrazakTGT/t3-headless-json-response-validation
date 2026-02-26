// =============================================================================
// playwright/tests/headless-json.spec.ts
// Tests E2E Playwright utilisant les snapshots PHPUnit comme source de vérité.
//
// ⚠️  Prérequis : les snapshots doivent être générés par PHPUnit
//     avant l'exécution de ces tests.
//     En CI : le stage "prepare" les génère et les publie en artifacts.
//     En local : UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...
// =============================================================================

import { test, expect } from '@playwright/test'
import { readFileSync, existsSync } from 'fs'
import { resolve } from 'path'

// Chemin vers les snapshots générés par PHPUnit
const SNAPSHOTS_DIR = resolve(__dirname, '../../Tests/Fixtures/Snapshots')

/**
 * Charge un snapshot PHPUnit. Lance une erreur claire si absent.
 */
function loadSnapshot(name: string): Record<string, unknown> {
  const path = resolve(SNAPSHOTS_DIR, `${name}.json`)
  if (!existsSync(path)) {
    throw new Error(
      `Snapshot "${name}.json" introuvable dans ${SNAPSHOTS_DIR}.\n` +
      `Générez-le : UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...`
    )
  }
  return JSON.parse(readFileSync(path, 'utf-8'))
}

// =============================================================================
// Tests API — validation des headers et structure JSON
// =============================================================================

test.describe('API JSON — structure et headers', () => {
  test('GET /api/pages/2 retourne un JSON valide avec les zones attendues', async ({ request }) => {
    const response = await request.get('/api/pages/2')

    expect(response.status()).toBe(200)
    expect(response.headers()['content-type']).toContain('application/json')

    const body = await response.json()
    expect(body).toHaveProperty('id')
    expect(body).toHaveProperty('meta')
    expect(body).toHaveProperty('i18n')
    expect(body).toHaveProperty('breadcrumbs')
    expect(body).toHaveProperty('appearance')
    expect(body).toHaveProperty('content')
  })

  test('La zone meta contient les champs SEO requis', async ({ request }) => {
    const response = await request.get('/api/pages/2')
    const body = await response.json()

    expect(typeof body.meta.title).toBe('string')
    expect(body.meta.title.length).toBeGreaterThan(0)
    expect(body.meta.robots).toMatch(/^(index|noindex),(follow|nofollow)$/)
  })
})

// =============================================================================
// Tests de rendu — utilise les snapshots comme référence
// =============================================================================

test.describe('Rendu page avec contenu', () => {
  let snapshot: Record<string, unknown>

  test.beforeAll(() => {
    snapshot = loadSnapshot('page_with_content')
  })

  test('Le titre de la page est affiché', async ({ page }) => {
    await page.goto((snapshot as any).slug)
    await expect(page).toHaveTitle(new RegExp((snapshot as any).meta.title))
  })

  test('Le fil d\'Ariane est complet', async ({ page }) => {
    await page.goto((snapshot as any).slug)
    const items = page.locator('[data-testid="breadcrumb-item"]')
    await expect(items).toHaveCount((snapshot as any).breadcrumbs.length)
  })

  test('Le premier breadcrumb pointe vers /', async ({ page }) => {
    await page.goto((snapshot as any).slug)
    const firstLink = page.locator('[data-testid="breadcrumb-item"] a').first()
    await expect(firstLink).toHaveAttribute('href', '/')
  })

  test('Les éléments de contenu colPos0 sont rendus', async ({ page }) => {
    await page.goto((snapshot as any).slug)
    const elements = page.locator('[data-testid="content-element"]')
    const expected = ((snapshot as any).content.colPos0 as unknown[]).length
    await expect(elements).toHaveCount(expected)
  })

  test('Les balises hreflang sont présentes dans le <head>', async ({ page }) => {
    await page.goto((snapshot as any).slug)
    const alternates = (snapshot as any).i18n.alternates as Array<{urlLocale: string, href: string}>

    for (const alt of alternates) {
      const hreflang = page.locator(`link[rel="alternate"][hreflang="${alt.urlLocale}"]`)
      await expect(hreflang).toHaveCount(1)
    }
  })
})

// =============================================================================
// Tests snapshot partiel meta — cohérence API ↔ rendu HTML
// =============================================================================

test.describe('Cohérence meta JSON ↔ balises HTML', () => {
  let metaSnapshot: Record<string, unknown>

  test.beforeAll(() => {
    metaSnapshot = loadSnapshot('page_with_content.meta')
  })

  test('La balise <title> correspond au snapshot meta.title', async ({ page }) => {
    await page.goto('/test-page-with-content')
    await expect(page).toHaveTitle(new RegExp(metaSnapshot.title as string))
  })

  test('La balise og:title correspond au snapshot meta.ogTitle', async ({ page }) => {
    if (!metaSnapshot.ogTitle) test.skip()
    await page.goto('/test-page-with-content')
    const ogTitle = page.locator('meta[property="og:title"]')
    await expect(ogTitle).toHaveAttribute('content', metaSnapshot.ogTitle as string)
  })

  test('La balise robots correspond au snapshot meta.robots', async ({ page }) => {
    await page.goto('/test-page-with-content')
    const robots = page.locator('meta[name="robots"]')
    await expect(robots).toHaveAttribute('content', metaSnapshot.robots as string)
  })
})
