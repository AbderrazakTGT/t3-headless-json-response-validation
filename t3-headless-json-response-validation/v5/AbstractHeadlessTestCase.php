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
 * SOURCE DE VÉRITÉ : tests/database/typo3_test.sql.gz
 *   → dump SQL de la base EC2 de référence, versionné dans Git
 *   → importé dans DDEV par chaque développeur : ./Tests/Scripts/import_dump.sh
 *   → importé dans le CI automatiquement avant les tests
 *   → mis à jour après chaque merge sur main (via cleanup EC2 + export)
 *
 * SNAPSHOTS : gitignorés, générés localement par chaque développeur
 *   → UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...
 *   → les snapshots reflètent les données locales du développeur
 *   → le CI valide les snapshots commitables contre la base stable
 *
 * COMPORTEMENT EN CI SUR UNE MR :
 *   → Les tests peuvent échouer si la feature nécessite des données
 *     pas encore dans la base stable (comportement attendu et documenté)
 *   → Après merge : mettre à jour la base EC2 et exporter un nouveau dump
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
     * FE users disponibles dans la base de référence :
     *   - UID défini dans les données de la base EC2 (voir tests/database/README.md)
     *
     * @param int $pageUid   UID de la page protégée
     * @param int $feUserUid UID du fe_user de test
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
            sprintf(
                'Réponse headless invalide pour page %d (fe_user %d) : %s',
                $pageUid,
                $feUserUid,
                $body
            )
        );

        return $decoded;
    }

    /**
     * Retourne le code HTTP d'une requête non authentifiée sur une page protégée.
     */
    protected function getHeadlessResponseCode(int $pageUid): int
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        return $this->executeFrontendSubRequest($request)->getStatusCode();
    }

    // =========================================================================
    // Snapshots — gitignorés, générés localement par chaque développeur
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
     * Crée/met à jour le snapshot si UPDATE_SNAPSHOTS=1.
     *
     * Les snapshots sont gitignorés — générés localement par chaque développeur
     * à partir de sa base locale (qui peut avoir des données de feature).
     * Le CI valide les tests mais ne génère pas de snapshots.
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
            self::markTestSkipped(
                'Snapshot "' . $snapshotName . '" généré. Relancez sans UPDATE_SNAPSHOTS.'
            );
        }

        self::assertJsonStringEqualsJsonFile(
            $snapshotFile,
            $json,
            'Snapshot "' . $snapshotName . '" ne correspond plus à la réponse. '
                . 'Si le changement est volontaire : UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ...'
        );
    }

    // =========================================================================
    // Validation JSON Schema (schemas versionnés dans Git — aucune donnée)
    // =========================================================================

    /**
     * Valide la réponse contre le schema principal du scénario.
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
                '/^https?:\/\//', $meta['canonical'],
                'meta.canonical doit être une URL absolue' . $ctx
            );
        }
    }

    /** Zone i18n */
    protected function assertValidI18nZone(array $i18n, string $expectedLocale = '', string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';
        foreach (['language', 'locale', 'hreflang', 'alternates'] as $key) {
            self::assertArrayHasKey($key, $i18n, 'i18n.' . $key . ' manquant' . $ctx);
        }
        if ($expectedLocale !== '') {
            self::assertSame($expectedLocale, $i18n['locale'], 'i18n.locale inattendu' . $ctx);
        }
    }

    /** Zone breadcrumbs */
    protected function assertValidBreadcrumbsZone(array $breadcrumbs, string $context = ''): void
    {
        $ctx = $context ? ' [' . $context . ']' : '';
        self::assertNotEmpty($breadcrumbs, 'breadcrumbs vide' . $ctx);
        self::assertSame('/', $breadcrumbs[0]['link'] ?? null, 'Premier breadcrumb doit être /' . $ctx);
        $last = end($breadcrumbs);
        self::assertTrue($last['current'] ?? false, 'Dernier breadcrumb doit avoir current=true' . $ctx);
    }

    /** Zone content */
    protected function assertValidContentZone(array $content, array $expectedColPos = ['colPos0']): void
    {
        foreach ($expectedColPos as $colPos) {
            self::assertArrayHasKey($colPos, $content, 'content.' . $colPos . ' manquant');
            self::assertIsArray($content[$colPos], 'content.' . $colPos . ' doit être un tableau');
        }
    }

    /** Accès non authentifié — doit être refusé (302 ou 403) */
    protected function assertUnauthenticatedAccessDenied(int $pageUid): void
    {
        $code = $this->getHeadlessResponseCode($pageUid);
        self::assertContains(
            $code,
            [302, 403],
            sprintf('Page %d devrait retourner 302/403 sans auth, reçu %d', $pageUid, $code)
        );
    }
}
