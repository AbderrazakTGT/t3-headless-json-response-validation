#!/bin/bash
# Script de génération automatique des tests headless TYPO3 v13

# Configuration
PROJECT_ROOT="/var/www/html/typo3"
TEST_DIR="Tests/Functional/Headless"
FIXTURE_DIR="Tests/Fixtures"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🚀 GÉNÉRATION DES TESTS HEADLESS TYPO3 v13"
echo "=========================================="

# Création des répertoires
echo -e "\n📁 Création de l'arborescence..."
mkdir -p {$TEST_DIR,$FIXTURE_DIR/Database,$FIXTURE_DIR/Schemas,$FIXTURE_DIR/Snapshots}

# [CORRECTIF] Création des dossiers de fixtures pour chaque scénario
# Les CSV doivent être maintenus manuellement avec des UIDs stables,
# sans champs dynamiques (crdate, tstamp, lastUpdated).
# La fonction extract_fixture() via mysql+sed a été supprimée car elle
# produisait un format CSV invalide non compatible avec importCSVDataSet().
for scenario in page_simple page_with_content page_with_images page_with_categories; do
    mkdir -p "$FIXTURE_DIR/Database/$scenario"
done

echo -e "${GREEN}✓${NC} Structure créée"
echo -e "${YELLOW}⚠${NC}  Remplissez manuellement les CSV dans $FIXTURE_DIR/Database/"
echo -e "   Format requis : uid,pid,... (sans crdate/tstamp/lastUpdated)"

# Fonction pour générer le test PHPUnit
# [CORRECTIF] Utilise executeFrontendSubRequest() + InternalRequest (API TYPO3 v13)
#             au lieu de getFrontendResponse() qui est déprécié depuis v12.
# [CORRECTIF] Snapshot généré par le test lui-même via UPDATE_SNAPSHOTS=1,
#             plus de curl externe sur http://localhost.
generate_test() {
    local scenario=$1
    local page_uid=$2
    local class_name=""

    # Conversion snake_case -> PascalCase
    IFS='_' read -ra parts <<< "$scenario"
    for part in "${parts[@]}"; do
        class_name+="${part^}"
    done

    local test_file="$TEST_DIR/${class_name}Test.php"

    echo -e "\n📝 Génération du test: ${YELLOW}${class_name}Test.php${NC}"

    cat > "$test_file" << EOF
<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

use TYPO3\TestingFramework\Core\Functional\FunctionalTestCase;
use TYPO3\TestingFramework\Core\Functional\Framework\Frontend\InternalRequest;
use JsonSchema\Validator;

/**
 * Test case for ${scenario} JSON response
 *
 * Pour régénérer les snapshots :
 *   UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless
 */
class ${class_name}Test extends FunctionalTestCase
{
    protected array \$testExtensionsToLoad = [
        'typo3conf/ext/headless',
        'typo3conf/ext/my_extension',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        \$this->importCSVDataSet(__DIR__ . '/../../Fixtures/Database/${scenario}/pages.csv');

        // Import des tables additionnelles si elles existent
        \$additionalTables = [
            'tt_content',
            'sys_file',
            'sys_file_reference',
            'sys_category',
            'sys_category_record_mm',
        ];
        foreach (\$additionalTables as \$table) {
            \$file = __DIR__ . '/../../Fixtures/Database/${scenario}/' . \$table . '.csv';
            if (file_exists(\$file)) {
                \$this->importCSVDataSet(\$file);
            }
        }
    }

    /**
     * @test
     */
    public function jsonResponseMatchesSchema(): void
    {
        // [CORRECTIF] executeFrontendSubRequest() + InternalRequest remplace getFrontendResponse()
        \$request = new InternalRequest('https://website.local/');
        \$request = \$request->withQueryParameter('id', ${page_uid});
        \$response = \$this->executeFrontendSubRequest(\$request);

        \$json = json_decode((string)\$response->getBody());

        \$validator = new Validator();
        \$schemaFile = __DIR__ . '/../../Fixtures/Schemas/${scenario}.schema.json';
        \$schemaData = json_decode(file_get_contents(\$schemaFile));

        \$validator->validate(\$json, \$schemaData);

        \$this->assertTrue(
            \$validator->isValid(),
            'JSON Schema validation failed: ' . json_encode(\$validator->getErrors())
        );
    }

    /**
     * @test
     */
    public function jsonResponseMatchesSnapshot(): void
    {
        // [CORRECTIF] executeFrontendSubRequest() + InternalRequest remplace getFrontendResponse()
        \$request = new InternalRequest('https://website.local/');
        \$request = \$request->withQueryParameter('id', ${page_uid});
        \$response = \$this->executeFrontendSubRequest(\$request);

        \$actual = (string)\$response->getBody();
        \$snapshotFile = __DIR__ . '/../../Fixtures/Snapshots/${scenario}.json';

        // [CORRECTIF] Génération du snapshot depuis le test lui-même,
        // plus de curl externe. Lancer avec UPDATE_SNAPSHOTS=1 pour régénérer.
        if (!file_exists(\$snapshotFile) || getenv('UPDATE_SNAPSHOTS') === '1') {
            \$pretty = json_encode(json_decode(\$actual), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            file_put_contents(\$snapshotFile, \$pretty);
            \$this->markTestSkipped('Snapshot généré. Relancez les tests sans UPDATE_SNAPSHOTS.');
        }

        \$this->assertJsonStringEqualsJsonFile(
            \$snapshotFile,
            \$actual,
            'JSON response does not match snapshot'
        );
    }
}
EOF

    echo -e "${GREEN}✓${NC} Test généré: $test_file"
}

# Exécution principale
echo -e "\n=========================================="
echo "🏗️  GÉNÉRATION DES SCÉNARIOS"
echo "=========================================="

# Scénario 1: Page simple
generate_test "page_simple" 1

# Scénario 2: Page avec contenu
generate_test "page_with_content" 2

# Scénario 3: Page avec images
generate_test "page_with_images" 3

# Scénario 4: Page avec catégories
generate_test "page_with_categories" 4

echo -e "\n=========================================="
echo -e "${GREEN}✅ GÉNÉRATION TERMINÉE AVEC SUCCÈS${NC}"
echo "=========================================="
echo -e "📁 Tests créés dans: ${YELLOW}$TEST_DIR${NC}"
echo -e "📁 Fixtures dans:    ${YELLOW}$FIXTURE_DIR${NC}"
echo -e "📁 Snapshots dans:   ${YELLOW}$FIXTURE_DIR/Snapshots${NC}"
echo ""
echo -e "👉 Prochaines étapes :"
echo -e "   1. Remplir les CSV dans $FIXTURE_DIR/Database/"
echo -e "   2. UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ... (génère les snapshots)"
echo -e "   3. vendor/bin/phpunit ... (mode vérification normal)"
echo "=========================================="
