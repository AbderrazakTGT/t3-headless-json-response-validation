<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

use TYPO3\TestingFramework\Core\Functional\FunctionalTestCase;
use TYPO3\TestingFramework\Core\Functional\Framework\Frontend\InternalRequest;
use JsonSchema\Validator;

/**
 * Classe de base pour les tests headless TYPO3 v13.
 *
 * Valide toutes les zones d'une réponse TYPO3 headless :
 *   - content (colPos)     → données de contenu
 *   - meta                 → SEO (title, robots, canonical, og:*)
 *   - i18n                 → langue, locale, hreflang, alternates
 *   - breadcrumbs          → fil d'Ariane
 *   - appearance           → layout, backendLayout
 *
 * Chaque zone est validée via :
 *   1. JSON Schema partiel ($ref)
 *   2. Snapshot partiel (diff Git lisible par zone)
 *   3. Assertions métier ciblées
 *
 * ⚠️  SÉCURITÉ :
 *   - Les fixtures CSV sont gitignorées — générées localement
 *   - Les snapshots sont gitignorés — générés localement
 *   - Aucune donnée sensible dans ce fichier (versionné)
 */
abstract class AbstractHeadlessTestCase extends FunctionalTestCase
{
    protected array $testExtensionsToLoad = [
        'typo3conf/ext/headless',
        'typo3conf/ext/my_extension',
    ];

    // -------------------------------------------------------------------------
    // Requêtes — API TYPO3 v13
    // executeFrontendSubRequest() remplace getFrontendResponse() (déprécié v12+)
    // -------------------------------------------------------------------------

    /**
     * Retourne la réponse JSON complète décodée en tableau PHP.
     */
    protected function getHeadlessResponse(int $pageUid): array
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        $body    = (string)$this->executeFrontendSubRequest($request)->getBody();
        $decoded = json_decode($body, true);

        self::assertIsArray($decoded, 'Réponse headless invalide pour page ' . $pageUid . ' : ' . $body);

        return $decoded;
    }

    /**
     * Retourne la réponse brute (string) pour les snapshots globaux.
     */
    protected function getHeadlessResponseRaw(int $pageUid): string
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        return (string)$this->executeFrontendSubRequest($request)->getBody();
    }

    // -------------------------------------------------------------------------
    // Fixtures CSV
    // Les CSV sont gitignorés — générés par generate_fixtures.sh
    // -------------------------------------------------------------------------

    /**
     * Importe les fixtures CSV d'un scénario.
     * pages.csv est obligatoire. Les autres tables sont chargées si présentes.
     */
    protected function importScenarioFixtures(string $scenario): void
    {
        $baseDir = __DIR__ . '/../../Fixtures/Database/' . $scenario;

        self::assertFileExists(
            $baseDir . '/pages.csv',
            'Fixtures manquantes pour "' . $scenario . '". Lancez : ./Tests/Scripts/generate_fixtures.sh'
        );

        $this->importCSVDataSet($baseDir . '/pages.csv');

        foreach ([
            'tt_content',
            'sys_file',
            'sys_file_reference',
            'sys_category',
            'sys_category_record_mm',
        ] as $table) {
            $file = $baseDir . '/' . $table . '.csv';
            if (file_exists($file)) {
                $this->importCSVDataSet($file);
            }
        }
    }

    // -------------------------------------------------------------------------
    // Validation JSON Schema (partiels $ref — versionnés)
    // -------------------------------------------------------------------------

    /**
     * Valide la réponse complète contre le schema principal du scénario.
     * Le schema référence les partiels via $ref.
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
            'Schema "' . $scenario . '" invalide : ' . json_encode($validator->getErrors(), JSON_PRETTY_PRINT)
        );
    }

    /**
     * Valide une zone contre un schema partiel.
     *
     * Exemple :
     *   $this->assertZoneMatchesSchema($response['meta'], 'partials/meta');
     */
    protected function assertZoneMatchesSchema(mixed $zone, string $partialName): void
    {
        $schemaFile = __DIR__ . '/../../Fixtures/Schemas/' . $partialName . '.schema.json';
        self::assertFileExists($schemaFile, 'Schema partiel introuvable : ' . $schemaFile);

        $validator  = new Validator();
        $schemaData = json_decode(file_get_contents($schemaFile));
        $json       = json_decode(json_encode($zone));

        $validator->validate($json, $schemaData);

        self::assertTrue(
            $validator->isValid(),
            'Schema partiel "' . $partialName . '" invalide : ' . json_encode($validator->getErrors(), JSON_PRETTY_PRINT)
        );
    }

    // -------------------------------------------------------------------------
    // Snapshots (gitignorés — générés localement et en CI comme artifact)
    // -------------------------------------------------------------------------

    /**
     * Compare la réponse brute avec le snapshot global.
     */
    protected function assertMatchesSnapshot(string $rawResponse, string $scenario): void
    {
        $this->assertPartialSnapshot($rawResponse, $scenario);
    }

    /**
     * Compare une zone avec son snapshot partiel.
     * Crée le snapshot si absent ou si UPDATE_SNAPSHOTS=1.
     *
     * ⚠️  Les snapshots sont gitignorés — ne pas commiter Tests/Fixtures/Snapshots/
     */
    protected function assertPartialSnapshot(mixed $data, string $snapshotName): void
    {
        $snapshotFile = __DIR__ . '/../../Fixtures/Snapshots/' . $snapshotName . '.json';
        $json = is_string($data)
            ? $data
            : json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

        if (!file_exists($snapshotFile) || getenv('UPDATE_SNAPSHOTS') === '1') {
            $dir = dirname($snapshotFile);
            if (!is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
            file_put_contents(
                $snapshotFile,
                json_encode(json_decode($json), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)
            );
            self::markTestSkipped('Snapshot "' . $snapshotName . '" généré. Relancez sans UPDATE_SNAPSHOTS.');
        }

        self::assertJsonStringEqualsJsonFile(
            $snapshotFile,
            $json,
            'Snapshot "' . $snapshotName . '" ne correspond plus à la réponse.'
        );
    }

    // -------------------------------------------------------------------------
    // Assertions métier par zone
    // -------------------------------------------------------------------------

    /**
     * Règles métier zone meta (SEO).
     */
    protected function assertValidMetaZone(array $meta, string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        self::assertNotEmpty($meta['title'] ?? '', 'meta.title vide' . $ctx);

        if (isset($meta['robots'])) {
            self::assertMatchesRegularExpression(
                '/^(index|noindex),(follow|nofollow)$/',
                $meta['robots'],
                'meta.robots invalide' . $ctx
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
     * Règles métier zone i18n.
     */
    protected function assertValidI18nZone(array $i18n, string $expectedLocale = '', string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        foreach (['language', 'locale', 'hreflang', 'alternates'] as $key) {
            self::assertArrayHasKey($key, $i18n, 'i18n.' . $key . ' manquant' . $ctx);
        }

        if ($expectedLocale !== '') {
            self::assertSame($expectedLocale, $i18n['locale'], 'i18n.locale inattendu' . $ctx);
        }

        foreach ($i18n['alternates'] as $idx => $alt) {
            self::assertArrayHasKey('urlLocale', $alt, 'i18n.alternates[' . $idx . '].urlLocale manquant' . $ctx);
            self::assertArrayHasKey('href', $alt, 'i18n.alternates[' . $idx . '].href manquant' . $ctx);
        }
    }

    /**
     * Règles métier zone breadcrumbs.
     */
    protected function assertValidBreadcrumbsZone(array $breadcrumbs, string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        self::assertNotEmpty($breadcrumbs, 'breadcrumbs vide' . $ctx);
        self::assertSame('/', $breadcrumbs[0]['link'] ?? null, 'Premier breadcrumb doit être /' . $ctx);

        $current = array_filter($breadcrumbs, fn($b) => ($b['current'] ?? false) === true);
        self::assertCount(1, $current, 'Un seul breadcrumb doit avoir current=true' . $ctx);
        self::assertTrue(end($breadcrumbs)['current'] ?? false, 'Dernier breadcrumb doit avoir current=true' . $ctx);
    }

    /**
     * Règles métier zone content (colPos).
     */
    protected function assertValidContentZone(array $content, array $expectedColPos = ['colPos0']): void
    {
        foreach ($expectedColPos as $colPos) {
            self::assertArrayHasKey($colPos, $content, 'content.' . $colPos . ' manquant');
            self::assertIsArray($content[$colPos], 'content.' . $colPos . ' doit être un tableau');
        }
    }
}
