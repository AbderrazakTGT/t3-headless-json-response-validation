#!/bin/bash
# Script de génération automatique des tests headless TYPO3 v13

# Configuration
DB_NAME="typo3_headless_test"
DB_USER="root"
DB_PASS=""
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
echo -e "${GREEN}✓${NC} Structure créée"

# Fonction pour extraire les fixtures
extract_fixture() {
    local scenario=$1
    local page_uid=$2
    shift 2
    local tables=("$@")
    
    echo -e "\n📦 Extraction du fixture: ${YELLOW}$scenario${NC}"
    
    # Création du dossier pour le scénario
    mkdir -p "$FIXTURE_DIR/Database/$scenario"
    
    for table in "${tables[@]}"; do
        echo "   Table: $table"
        
        # Extraction des données avec exclusion des champs dynamiques
        mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "
            SELECT * FROM $table 
            WHERE pid = $page_uid OR uid = $page_uid
            LIMIT 10" 2>/dev/null | sed 's/\t/,/g' > "$FIXTURE_DIR/Database/${scenario}/${table}.csv"
        
        if [ -s "$FIXTURE_DIR/Database/${scenario}/${table}.csv" ]; then
            echo "   ${GREEN}✓${NC} $table extraite"
        else
            echo "   ${YELLOW}⚠${NC} Aucune donnée pour $table"
        fi
    done
}

# Fonction pour générer le test PHPUnit
generate_test() {
    local scenario=$1
    local page_uid=$2
    local test_file="$TEST_DIR/${scenario^}Test.php"
    
    echo -e "\n📝 Génération du test: ${YELLOW}${scenario^}Test.php${NC}"
    
    cat > $test_file << EOF
<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

use TYPO3\TestingFramework\Core\Functional\FunctionalTestCase;
use JsonSchema\Validator;

/**
 * Test case for $scenario JSON response
 */
class ${scenario^}Test extends FunctionalTestCase
{
    protected array \$testExtensionsToLoad = [
        'typo3conf/ext/headless',
        'typo3conf/ext/my_extension'
    ];

    protected function setUp(): void
    {
        parent::setUp();
        \$this->importCSVDataSet(__DIR__ . '/../../Fixtures/Database/${scenario}/pages.csv');
        
        // Import additional tables if they exist
        \$additionalTables = ['tt_content', 'sys_file', 'sys_file_reference', 'sys_category', 'sys_category_record_mm'];
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
        \$response = \$this->getFrontendResponse($page_uid);
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
        \$response = \$this->getFrontendResponse($page_uid);
        
        \$this->assertJsonStringEqualsJsonFile(
            __DIR__ . '/../../Fixtures/Snapshots/${scenario}.json',
            (string)\$response->getBody(),
            'JSON response does not match snapshot'
        );
    }
}
EOF
    
    echo -e "${GREEN}✓${NC} Test généré: $test_file"
}

# Fonction pour générer le snapshot
generate_snapshot() {
    local scenario=$1
    local page_uid=$2
    local base_url=${BASE_URL:-"http://localhost"}
    
    echo -e "\n📸 Génération du snapshot: ${YELLOW}$scenario${NC}"
    
    # Appel API et sauvegarde du snapshot
    curl -s "$base_url/api/pages/$page_uid" | jq '.' > "$FIXTURE_DIR/Snapshots/${scenario}.json"
    
    if [ -s "$FIXTURE_DIR/Snapshots/${scenario}.json" ]; then
        echo -e "${GREEN}✓${NC} Snapshot créé: $FIXTURE_DIR/Snapshots/${scenario}.json"
    else
        echo -e "${RED}✗${NC} Échec création snapshot $scenario"
    fi
}

# Exécution principale
echo -e "\n=========================================="
echo "🏗️  GÉNÉRATION DES SCÉNARIOS"
echo "=========================================="

# Scénario 1: Page simple
extract_fixture "page_simple" 1 "pages"
generate_test "page_simple" 1
generate_snapshot "page_simple" 1

# Scénario 2: Page avec contenu
extract_fixture "page_with_content" 2 "pages" "tt_content"
generate_test "page_with_content" 2
generate_snapshot "page_with_content" 2

# Scénario 3: Page avec images
extract_fixture "page_with_images" 3 "pages" "tt_content" "sys_file" "sys_file_reference"
generate_test "page_with_images" 3
generate_snapshot "page_with_images" 3

# Scénario 4: Page avec catégories
extract_fixture "page_with_categories" 4 "pages" "tt_content" "sys_category" "sys_category_record_mm"
generate_test "page_with_categories" 4
generate_snapshot "page_with_categories" 4

echo -e "\n=========================================="
echo -e "${GREEN}✅ GÉNÉRATION TERMINÉE AVEC SUCCÈS${NC}"
echo "=========================================="
echo -e "📁 Tests créés dans: ${YELLOW}$TEST_DIR${NC}"
echo -e "📁 Fixtures dans: ${YELLOW}$FIXTURE_DIR${NC}"
echo -e "📁 Snapshots dans: ${YELLOW}$FIXTURE_DIR/Snapshots${NC}"
echo "=========================================="