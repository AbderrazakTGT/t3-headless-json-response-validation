#!/bin/bash
# =============================================================================
# generate_headless_tests.sh
# Génère les fichiers PHP de test (versionnés dans Git).
# Aucune donnée — uniquement du code PHP.
# =============================================================================

TEST_DIR="Tests/Functional/Headless"
FIXTURE_DIR="Tests/Fixtures"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🚀 GÉNÉRATION DES TESTS HEADLESS TYPO3 v13"
echo "=========================================="

mkdir -p "$TEST_DIR" \
  "$FIXTURE_DIR/Database" \
  "$FIXTURE_DIR/Schemas" \
  "$FIXTURE_DIR/Snapshots"

# =============================================================================
# Génère un fichier PHP de test pour un scénario donné
# =============================================================================
generate_test() {
    local scenario=$1
    local page_uid=$2
    local class_name=""

    IFS='_' read -ra parts <<< "$scenario"
    for part in "${parts[@]}"; do
        class_name+="${part^}"
    done

    local test_file="$TEST_DIR/${class_name}Test.php"
    echo -e "\n📝 Génération : ${YELLOW}${class_name}Test.php${NC}"

    cat > "$test_file" << EOF
<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

/**
 * Test JSON headless pour le scénario : ${scenario}
 *
 * Valide toutes les zones de la réponse TYPO3 headless :
 *   - Structure globale    → JSON Schema principal + snapshot global
 *   - meta (SEO)           → schema partiel + snapshot partiel + assertions métier
 *   - i18n                 → schema partiel + snapshot partiel + assertions métier
 *   - breadcrumbs          → schema partiel + snapshot partiel + assertions métier
 *   - appearance / layout  → schema partiel + snapshot partiel
 *   - content (colPos)     → schema partiel + snapshot partiel + assertions structure
 *
 * ⚠️  Les fixtures CSV sont gitignorées — générées par :
 *   ./Tests/Scripts/generate_fixtures.sh
 *
 * Pour régénérer les snapshots (gitignorés) :
 *   UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \\
 *     -c typo3/sysext/core/Build/FunctionalTests.xml \\
 *     Tests/Functional/Headless
 */
class ${class_name}Test extends AbstractHeadlessTestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        \$this->importScenarioFixtures('${scenario}');
    }

    // -----------------------------------------------------------------------
    // 1. Schema global
    // -----------------------------------------------------------------------

    /** @test */
    public function jsonResponseMatchesGlobalSchema(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});
        \$this->assertMatchesJsonSchema(\$response, '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 2. Snapshot global
    // -----------------------------------------------------------------------

    /** @test */
    public function jsonResponseMatchesGlobalSnapshot(): void
    {
        \$raw = \$this->getHeadlessResponseRaw(${page_uid});
        \$this->assertMatchesSnapshot(\$raw, '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 3. Zone meta (SEO)
    // -----------------------------------------------------------------------

    /** @test */
    public function metaZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('meta', \$response, 'Zone meta absente');
        \$this->assertZoneMatchesSchema(\$response['meta'], 'partials/meta');
        \$this->assertPartialSnapshot(\$response['meta'], '${scenario}.meta');
        \$this->assertValidMetaZone(\$response['meta'], '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 4. Zone i18n
    // -----------------------------------------------------------------------

    /** @test */
    public function i18nZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('i18n', \$response, 'Zone i18n absente');
        \$this->assertZoneMatchesSchema(\$response['i18n'], 'partials/i18n');
        \$this->assertPartialSnapshot(\$response['i18n'], '${scenario}.i18n');
        \$this->assertValidI18nZone(\$response['i18n'], '', '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 5. Zone breadcrumbs
    // -----------------------------------------------------------------------

    /** @test */
    public function breadcrumbsZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('breadcrumbs', \$response, 'Zone breadcrumbs absente');
        \$this->assertZoneMatchesSchema(\$response['breadcrumbs'], 'partials/breadcrumbs');
        \$this->assertPartialSnapshot(\$response['breadcrumbs'], '${scenario}.breadcrumbs');
        \$this->assertValidBreadcrumbsZone(\$response['breadcrumbs'], '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 6. Zone appearance
    // -----------------------------------------------------------------------

    /** @test */
    public function appearanceZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('appearance', \$response, 'Zone appearance absente');
        \$this->assertZoneMatchesSchema(\$response['appearance'], 'partials/appearance');
        \$this->assertPartialSnapshot(\$response['appearance'], '${scenario}.appearance');
    }

    // -----------------------------------------------------------------------
    // 7. Zone content (colPos)
    // -----------------------------------------------------------------------

    /** @test */
    public function contentZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('content', \$response, 'Zone content absente');
        \$this->assertZoneMatchesSchema(\$response['content'], 'partials/content');
        \$this->assertPartialSnapshot(\$response['content'], '${scenario}.content');
        \$this->assertValidContentZone(\$response['content'], ['colPos0']);
    }
}
EOF

    echo -e "${GREEN}✓${NC} $test_file"
}

# =============================================================================
# Génération des 4 scénarios
# =============================================================================
echo -e "\n=========================================="
echo "🏗️  GÉNÉRATION DES SCÉNARIOS"
echo "=========================================="

generate_test "page_simple" 1
generate_test "page_with_content" 2
generate_test "page_with_images" 3
generate_test "page_with_categories" 4

echo -e "\n=========================================="
echo -e "${GREEN}✅ TESTS GÉNÉRÉS (versionnés dans Git)${NC}"
echo "=========================================="
echo -e "📁 Tests : ${YELLOW}$TEST_DIR${NC}"
echo ""
echo "Prochaines étapes :"
echo "  1. ./Tests/Scripts/generate_fixtures.sh    (fixtures locales)"
echo "  2. UPDATE_SNAPSHOTS=1 vendor/bin/phpunit   (snapshots locaux)"
echo "  3. vendor/bin/phpunit                      (vérification)"
echo "=========================================="
