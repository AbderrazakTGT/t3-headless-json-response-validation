<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

use TYPO3\TestingFramework\Core\Functional\FunctionalTestCase;
use TYPO3\TestingFramework\Core\Functional\Framework\Frontend\InternalRequest;
use TYPO3\TestingFramework\Core\Functional\Framework\Frontend\InternalRequestContext;
use JsonSchema\Validator;

/**
 * Classe de base pour les tests headless TYPO3 v13.
 *
 * Valide toutes les zones d'une réponse TYPO3 headless :
 *   content, meta, i18n, breadcrumbs, appearance
 *
 * Gère également l'authentification FE users pour les pages protégées.
 *
 * ✅ Fixtures CSV versionnées dans Git (anonymisées, ~50 Ko)
 * ❌ Snapshots gitignorés (générés localement)
 * ✅ Compatibilité travail hors-ligne
 */
abstract class AbstractHeadlessTestCase extends FunctionalTestCase
{
    protected array $testExtensionsToLoad = [
        'typo3conf/ext/headless',
        'typo3conf/ext/my_extension',
    ];

    // =========================================================================
    // Requêtes — API TYPO3 v13
    // executeFrontendSubRequest() remplace getFrontendResponse() (déprécié v12+)
    // =========================================================================

    /**
     * Retourne la réponse JSON décodée (page publique).
     */
    protected function getHeadlessResponse(int $pageUid): array
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        $body    = (string)$this->executeFrontendSubRequest($request)->getBody();
        $decoded = json_decode($body, true);

        self::assertIsArray(
            $decoded,
            'Réponse headless invalide pour page ' . $pageUid . ' : ' . $body
        );

        return $decoded;
    }

    /**
     * Retourne la réponse JSON brute (string) pour les snapshots globaux.
     */
    protected function getHeadlessResponseRaw(int $pageUid): string
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        return (string)$this->executeFrontendSubRequest($request)->getBody();
    }

    /**
     * Retourne la réponse JSON pour une page protégée en tant que FE user.
     *
     * @param int $pageUid  UID de la page
     * @param int $feUserUid UID du fe_user (100=standard, 101=premium, 102=admin)
     */
    protected function getHeadlessResponseAsFeUser(int $pageUid, int $feUserUid): array
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        $context = (new InternalRequestContext())
            ->withFrontendUserId($feUserUid);

        $body    = (string)$this->executeFrontendSubRequest($request, $context)->getBody();
        $decoded = json_decode($body, true);

        self::assertIsArray(
            $decoded,
            'Réponse headless invalide pour page ' . $pageUid . ' (fe_user ' . $feUserUid . ') : ' . $body
        );

        return $decoded;
    }

    /**
     * Retourne le code HTTP d'une requête sur une page protégée sans authentification.
     * Attendu : 403 ou redirect vers la page de login.
     */
    protected function getHeadlessResponseCode(int $pageUid): int
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        $response = $this->executeFrontendSubRequest($request);

        return $response->getStatusCode();
    }

    // =========================================================================
    // Fixtures CSV
    // Versionnées dans Git après anonymisation — disponibles hors-ligne
    // =========================================================================

    /**
     * Importe les fixtures d'un scénario.
     * pages.csv est obligatoire — les autres tables sont chargées si présentes.
     *
     * Tables reconnues (ordre d'import important pour les FK) :
     *   fe_groups, fe_users, pages, tt_content,
     *   sys_file, sys_file_reference, sys_category, sys_category_record_mm
     */
    protected function importScenarioFixtures(string $scenario): void
    {
        $baseDir = __DIR__ . '/../../Fixtures/Database/' . $scenario;

        self::assertFileExists(
            $baseDir . '/pages.csv',
            sprintf(
                'Fixtures manquantes pour "%s". Lancez : ./Tests/Scripts/generate_fixtures.sh',
                $scenario
            )
        );

        // Ordre d'import : tables sans FK d'abord
        $tables = [
            'fe_groups',
            'fe_users',
            'pages',
            'tt_content',
            'sys_file',
            'sys_file_reference',
            'sys_category',
            'sys_category_record_mm',
        ];

        foreach ($tables as $table) {
            $file = $baseDir . '/' . $table . '.csv';
            if (file_exists($file)) {
                $this->importCSVDataSet($file);
            }
        }
    }

    // =========================================================================
    // JSON Schema — partiels $ref (versionnés)
    // =========================================================================

    /**
     * Valide la réponse contre le schema principal du scénario.
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
            'Schema "' . $scenario . '" invalide : '
                . json_encode($validator->getErrors(), JSON_PRETTY_PRINT)
        );
    }

    /**
     * Valide une zone contre un schema partiel.
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
            'Schema partiel "' . $partialName . '" invalide : '
                . json_encode($validator->getErrors(), JSON_PRETTY_PRINT)
        );
    }

    // =========================================================================
    // Snapshots — gitignorés, générés localement
    // =========================================================================

    /**
     * Compare la réponse brute avec le snapshot global.
     */
    protected function assertMatchesSnapshot(string $rawResponse, string $scenario): void
    {
        $this->assertPartialSnapshot($rawResponse, $scenario);
    }

    /**
     * Compare une zone avec son snapshot partiel.
     * Génère le snapshot si absent ou si UPDATE_SNAPSHOTS=1.
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
                json_encode(
                    json_decode($json),
                    JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
                )
            );
            self::markTestSkipped('Snapshot "' . $snapshotName . '" généré. Relancez sans UPDATE_SNAPSHOTS.');
        }

        self::assertJsonStringEqualsJsonFile(
            $snapshotFile,
            $json,
            'Snapshot "' . $snapshotName . '" ne correspond plus à la réponse.'
        );
    }

    // =========================================================================
    // Assertions métier par zone
    // =========================================================================

    /** Zone meta — règles SEO */
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

    /** Zone i18n — règles internationalisation */
    protected function assertValidI18nZone(array $i18n, string $expectedLocale = '', string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        foreach (['language', 'locale', 'hreflang', 'alternates'] as $key) {
            self::assertArrayHasKey($key, $i18n, 'i18n.' . $key . ' manquant' . $ctx);
        }

        if ($expectedLocale !== '') {
            self::assertSame($expectedLocale, $i18n['locale'], 'i18n.locale inattendu' . $ctx);
        }

        foreach ($i18n['alternates'] ?? [] as $idx => $alt) {
            self::assertArrayHasKey('urlLocale', $alt, "i18n.alternates[$idx].urlLocale manquant" . $ctx);
            self::assertArrayHasKey('href',      $alt, "i18n.alternates[$idx].href manquant" . $ctx);
        }
    }

    /** Zone breadcrumbs — règles fil d'Ariane */
    protected function assertValidBreadcrumbsZone(array $breadcrumbs, string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';

        self::assertNotEmpty($breadcrumbs, 'breadcrumbs vide' . $ctx);
        self::assertSame('/', $breadcrumbs[0]['link'] ?? null, 'Premier breadcrumb doit être /' . $ctx);

        $current = array_filter($breadcrumbs, fn($b) => ($b['current'] ?? false) === true);
        self::assertCount(1, $current, 'Un seul breadcrumb doit avoir current=true' . $ctx);

        $last = end($breadcrumbs);
        self::assertTrue($last['current'] ?? false, 'Dernier breadcrumb doit avoir current=true' . $ctx);
    }

    /** Zone content — vérifie la présence des colPos */
    protected function assertValidContentZone(array $content, array $expectedColPos = ['colPos0']): void
    {
        foreach ($expectedColPos as $colPos) {
            self::assertArrayHasKey($colPos, $content, 'content.' . $colPos . ' manquant');
            self::assertIsArray($content[$colPos], 'content.' . $colPos . ' doit être un tableau');
        }
    }

    /**
     * Vérifie qu'un accès non authentifié à une page protégée est refusé.
     * TYPO3 retourne typiquement 403 ou redirige (302) vers la page de login.
     */
    protected function assertUnauthenticatedAccessDenied(int $pageUid): void
    {
        $code = $this->getHeadlessResponseCode($pageUid);
        self::assertContains(
            $code,
            [302, 403],
            sprintf(
                'Page protégée %d devrait retourner 302 ou 403 sans authentification, reçu %d',
                $pageUid,
                $code
            )
        );
    }
}
