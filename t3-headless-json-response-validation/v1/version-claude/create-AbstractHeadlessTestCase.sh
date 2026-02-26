#!/bin/bash
# ============================================================
# NOUVEAU FICHIER À CRÉER :
# Tests/Functional/Headless/AbstractHeadlessTestCase.php
# ============================================================
#
# Couvre la validation complète d'une réponse TYPO3 headless :
#   - données de contenu (content / colPos)
#   - métadonnées SEO (meta)
#   - internationalisation (i18n / hreflang / alternates)
#   - fil d'Ariane (breadcrumbs)
#   - apparence / layout (appearance)
#
# Ce fichier n'existait pas dans le projet original.
# Il factorise la logique commune à tous les tests headless :
#   - Chargement des extensions
#   - Import des CSV fixtures
#   - Méthode getHeadlessResponse() avec la nouvelle API TYPO3 v13
#
# Tous les tests (PageSimpleTest, PageWithContentTest, etc.)
# doivent étendre cette classe plutôt que FunctionalTestCase directement.

cat > Tests/Functional/Headless/AbstractHeadlessTestCase.php << 'PHPEOF'
<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

use TYPO3\TestingFramework\Core\Functional\FunctionalTestCase;
use TYPO3\TestingFramework\Core\Functional\Framework\Frontend\InternalRequest;
use JsonSchema\Validator;

/**
 * Classe de base pour les tests headless TYPO3 v13.
 *
 * Couvre la validation complète d'une réponse TYPO3 headless :
 *   - données de contenu (content / colPos)
 *   - métadonnées SEO (meta)
 *   - internationalisation (i18n / hreflang / alternates)
 *   - fil d'Ariane (breadcrumbs)
 *   - apparence / layout (appearance)
 *
 * Chaque zone est validée indépendamment via :
 *   1. Un JSON Schema partiel ($ref)
 *   2. Un snapshot partiel (diff lisible par zone)
 *   3. Des assertions ciblées pour les règles métier critiques
 */
abstract class AbstractHeadlessTestCase extends FunctionalTestCase
{
    protected array $testExtensionsToLoad = [
        'typo3conf/ext/headless',
        'typo3conf/ext/my_extension',
    ];

    // -------------------------------------------------------------------------
    // Requêtes
    // -------------------------------------------------------------------------

    /**
     * Retourne la réponse JSON complète décodée en tableau PHP.
     */
    protected function getHeadlessResponse(int $pageUid): array
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        $response = $this->executeFrontendSubRequest($request);
        $body     = (string)$response->getBody();
        $decoded  = json_decode($body, true);

        self::assertIsArray($decoded, 'La réponse headless n\'est pas un JSON valide : ' . $body);

        return $decoded;
    }

    /**
     * Retourne la réponse brute (string) pour les assertions de snapshot global.
     */
    protected function getHeadlessResponseRaw(int $pageUid): string
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        return (string)$this->executeFrontendSubRequest($request)->getBody();
    }

    // -------------------------------------------------------------------------
    // Fixtures
    // -------------------------------------------------------------------------

    /**
     * Importe les CSV fixtures d'un scénario.
     * pages.csv est obligatoire ; les autres tables sont chargées si présentes.
     */
    protected function importScenarioFixtures(string $scenario): void
    {
        $baseDir = __DIR__ . '/../../Fixtures/Database/' . $scenario;

        $this->importCSVDataSet($baseDir . '/pages.csv');

        foreach (['tt_content', 'sys_file', 'sys_file_reference', 'sys_category', 'sys_category_record_mm'] as $table) {
            $file = $baseDir . '/' . $table . '.csv';
            if (file_exists($file)) {
                $this->importCSVDataSet($file);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Validation JSON Schema (global + partiels $ref)
    // -------------------------------------------------------------------------

    /**
     * Valide la réponse complète contre le schema principal du scénario.
     * Le schema principal peut référencer des schemas partiels via $ref :
     *   "meta":        { "$ref": "partials/meta.schema.json" }
     *   "i18n":        { "$ref": "partials/i18n.schema.json" }
     *   "breadcrumbs": { "$ref": "partials/breadcrumbs.schema.json" }
     *   "appearance":  { "$ref": "partials/appearance.schema.json" }
     *   "content":     { "$ref": "partials/content.schema.json" }
     */
    protected function assertMatchesJsonSchema(array $response, string $scenario): void
    {
        $schemaFile = __DIR__ . '/../../Fixtures/Schemas/' . $scenario . '.schema.json';
        self::assertFileExists($schemaFile, 'Schema introuvable : ' . $schemaFile);

        $validator  = new Validator();
        $schemaData = json_decode(file_get_contents($schemaFile));
        $json       = json_decode(json_encode($response));

        $validator->validate($json, $schemaData);

        self::assertTrue(
            $validator->isValid(),
            'JSON Schema validation failed for "' . $scenario . '": '
                . json_encode($validator->getErrors(), JSON_PRETTY_PRINT)
        );
    }

    /**
     * Valide une zone spécifique de la réponse contre un schema partiel.
     *
     * Exemple :
     *   $this->assertZoneMatchesSchema($response['meta'], 'partials/meta');
     *   $this->assertZoneMatchesSchema($response['i18n'], 'partials/i18n');
     */
    protected function assertZoneMatchesSchema(mixed $zone, string $partialSchemaName): void
    {
        $schemaFile = __DIR__ . '/../../Fixtures/Schemas/' . $partialSchemaName . '.schema.json';
        self::assertFileExists($schemaFile, 'Schema partiel introuvable : ' . $schemaFile);

        $validator  = new Validator();
        $schemaData = json_decode(file_get_contents($schemaFile));
        $json       = json_decode(json_encode($zone));

        $validator->validate($json, $schemaData);

        self::assertTrue(
            $validator->isValid(),
            'Schema partiel "' . $partialSchemaName . '" invalide : '
                . json_encode($validator->getErrors(), JSON_PRETTY_PRINT)
        );
    }

    // -------------------------------------------------------------------------
    // Snapshots (global + partiels par zone)
    // -------------------------------------------------------------------------

    /**
     * Compare la réponse brute avec le snapshot global du scénario.
     * Lancer avec UPDATE_SNAPSHOTS=1 pour régénérer.
     */
    protected function assertMatchesSnapshot(string $rawResponse, string $scenario): void
    {
        $this->assertPartialSnapshot($rawResponse, $scenario);
    }

    /**
     * Compare une zone spécifique avec son snapshot partiel.
     * Permet des diffs Git lisibles par zone (meta, i18n, breadcrumbs...).
     *
     * Exemple :
     *   $this->assertPartialSnapshot($response['meta'], $scenario . '.meta');
     *   $this->assertPartialSnapshot($response['breadcrumbs'], $scenario . '.breadcrumbs');
     */
    protected function assertPartialSnapshot(mixed $data, string $snapshotName): void
    {
        $snapshotFile = __DIR__ . '/../../Fixtures/Snapshots/' . $snapshotName . '.json';
        $json         = is_string($data)
            ? $data
            : json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

        if (!file_exists($snapshotFile) || getenv('UPDATE_SNAPSHOTS') === '1') {
            $dir = dirname($snapshotFile);
            if (!is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
            $pretty = json_encode(
                json_decode($json),
                JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
            );
            file_put_contents($snapshotFile, $pretty);
            self::markTestSkipped('Snapshot "' . $snapshotName . '" généré. Relancez sans UPDATE_SNAPSHOTS.');
        }

        self::assertJsonStringEqualsJsonFile(
            $snapshotFile,
            $json,
            'Snapshot "' . $snapshotName . '" ne correspond plus à la réponse actuelle.'
        );
    }

    // -------------------------------------------------------------------------
    // Assertions métier par zone
    // -------------------------------------------------------------------------

    /**
     * Valide les règles métier critiques de la zone meta (SEO).
     * À appeler dans chaque test pour une couverture au-delà du schema.
     */
    protected function assertValidMetaZone(array $meta, string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        self::assertNotEmpty($meta['title'] ?? '', 'meta.title ne doit pas être vide' . $ctx);

        if (isset($meta['robots'])) {
            self::assertMatchesRegularExpression(
                '/^(index|noindex),(follow|nofollow)$/',
                $meta['robots'],
                'meta.robots a une valeur invalide' . $ctx
            );
        }

        if (isset($meta['canonical'])) {
            self::assertMatchesRegularExpression(
                '/^https?:\/\//',
                $meta['canonical'],
                'meta.canonical doit être une URL absolue' . $ctx
            );
        }

        if (isset($meta['ogImage'])) {
            self::assertStringStartsWith(
                '/fileadmin/',
                $meta['ogImage'],
                'meta.ogImage doit pointer vers /fileadmin/' . $ctx
            );
        }
    }

    /**
     * Valide les règles métier critiques de la zone i18n.
     */
    protected function assertValidI18nZone(array $i18n, string $expectedLocale = '', string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        self::assertArrayHasKey('language', $i18n, 'i18n.language manquant' . $ctx);
        self::assertArrayHasKey('locale', $i18n, 'i18n.locale manquant' . $ctx);
        self::assertArrayHasKey('hreflang', $i18n, 'i18n.hreflang manquant' . $ctx);
        self::assertArrayHasKey('alternates', $i18n, 'i18n.alternates manquant' . $ctx);

        if ($expectedLocale !== '') {
            self::assertSame($expectedLocale, $i18n['locale'], 'i18n.locale inattendu' . $ctx);
        }

        if (!empty($i18n['alternates'])) {
            foreach ($i18n['alternates'] as $idx => $alt) {
                self::assertArrayHasKey('urlLocale', $alt, 'i18n.alternates[' . $idx . '].urlLocale manquant' . $ctx);
                self::assertArrayHasKey('href', $alt, 'i18n.alternates[' . $idx . '].href manquant' . $ctx);
            }
        }
    }

    /**
     * Valide les règles métier critiques de la zone breadcrumbs.
     */
    protected function assertValidBreadcrumbsZone(array $breadcrumbs, string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        self::assertNotEmpty($breadcrumbs, 'breadcrumbs ne doit pas être vide' . $ctx);

        // Le premier élément doit toujours être la racine
        self::assertSame('/', $breadcrumbs[0]['link'] ?? null, 'Le premier breadcrumb doit pointer vers /' . $ctx);

        // Un seul élément doit être marqué current
        $currentItems = array_filter($breadcrumbs, fn($b) => ($b['current'] ?? false) === true);
        self::assertCount(1, $currentItems, 'Un seul breadcrumb doit avoir current=true' . $ctx);

        // Le dernier élément doit être current
        $last = end($breadcrumbs);
        self::assertTrue($last['current'] ?? false, 'Le dernier breadcrumb doit avoir current=true' . $ctx);
    }

    /**
     * Valide la présence et la structure des colPos dans la zone content.
     *
     * Exemple :
     *   $this->assertValidContentZone($response['content'], ['colPos0', 'colPos1']);
     */
    protected function assertValidContentZone(array $content, array $expectedColPos = ['colPos0']): void
    {
        foreach ($expectedColPos as $colPos) {
            self::assertArrayHasKey($colPos, $content, 'content.' . $colPos . ' manquant');
            self::assertIsArray($content[$colPos], 'content.' . $colPos . ' doit être un tableau');
        }
    }
}
PHPEOF

echo "✓ AbstractHeadlessTestCase.php créé dans Tests/Functional/Headless/"