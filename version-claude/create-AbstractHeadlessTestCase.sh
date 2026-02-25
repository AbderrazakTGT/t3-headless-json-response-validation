#!/bin/bash
# ============================================================
# NOUVEAU FICHIER À CRÉER :
# Tests/Functional/Headless/AbstractHeadlessTestCase.php
# ============================================================
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
use Psr\Http\Message\ResponseInterface;

/**
 * Classe de base pour les tests headless TYPO3 v13
 *
 * [CORRECTIF] Centralise l'utilisation de executeFrontendSubRequest()
 * qui remplace getFrontendResponse() déprécié depuis TYPO3 v12.
 */
abstract class AbstractHeadlessTestCase extends FunctionalTestCase
{
    protected array $testExtensionsToLoad = [
        'typo3conf/ext/headless',
        'typo3conf/ext/my_extension',
    ];

    /**
     * Retourne la réponse JSON headless pour une page donnée.
     *
     * [CORRECTIF] Utilise InternalRequest + executeFrontendSubRequest()
     * au lieu de getFrontendResponse($uid) qui est déprécié.
     */
    protected function getHeadlessResponse(int $pageUid): array
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        $response = $this->executeFrontendSubRequest($request);

        $body = (string)$response->getBody();
        $decoded = json_decode($body, true);

        self::assertIsArray($decoded, 'La réponse headless nest pas un JSON valide : ' . $body);

        return $decoded;
    }

    /**
     * Retourne la réponse brute (string) pour les assertions de snapshot.
     */
    protected function getHeadlessResponseRaw(int $pageUid): string
    {
        $request = (new InternalRequest('https://website.local/'))
            ->withQueryParameter('id', $pageUid);

        $response = $this->executeFrontendSubRequest($request);

        return (string)$response->getBody();
    }

    /**
     * Import des fixtures CSV pour un scénario donné.
     * Importe pages.csv obligatoirement, puis les tables optionnelles si présentes.
     */
    protected function importScenarioFixtures(string $scenario): void
    {
        $baseDir = __DIR__ . '/../../Fixtures/Database/' . $scenario;

        $this->importCSVDataSet($baseDir . '/pages.csv');

        $optionalTables = [
            'tt_content',
            'sys_file',
            'sys_file_reference',
            'sys_category',
            'sys_category_record_mm',
        ];

        foreach ($optionalTables as $table) {
            $file = $baseDir . '/' . $table . '.csv';
            if (file_exists($file)) {
                $this->importCSVDataSet($file);
            }
        }
    }
}
PHPEOF

echo "✓ AbstractHeadlessTestCase.php créé dans Tests/Functional/Headless/"
