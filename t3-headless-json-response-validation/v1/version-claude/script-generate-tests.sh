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

/**
 * Test case for ${scenario} JSON response.
 *
 * Valide toutes les zones de la réponse TYPO3 headless :
 *   - Structure globale   → JSON Schema principal + snapshot global
 *   - meta (SEO)          → schema partiel + snapshot partiel + assertions métier
 *   - i18n                → schema partiel + snapshot partiel + assertions métier
 *   - breadcrumbs         → schema partiel + snapshot partiel + assertions métier
 *   - appearance / layout → schema partiel + snapshot partiel
 *   - content (colPos)    → schema partiel + snapshot partiel + assertions structure
 *
 * Pour régénérer tous les snapshots :
 *   UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless
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

    /**
     * @test
     * Valide la structure complète de la réponse (toutes les zones)
     * contre le schema principal qui référence les schemas partiels via \$ref.
     */
    public function jsonResponseMatchesGlobalSchema(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});
        \$this->assertMatchesJsonSchema(\$response, '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 2. Snapshot global
    // -----------------------------------------------------------------------

    /**
     * @test
     * Détecte toute régression sur la réponse complète.
     * Un diff = soit une régression (corriger le code), soit un changement
     * volontaire (relancer avec UPDATE_SNAPSHOTS=1 et commiter).
     */
    public function jsonResponseMatchesGlobalSnapshot(): void
    {
        \$raw = \$this->getHeadlessResponseRaw(${page_uid});
        \$this->assertMatchesSnapshot(\$raw, '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 3. Zone meta (SEO)
    // -----------------------------------------------------------------------

    /**
     * @test
     */
    public function metaZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});

        \$this->assertArrayHasKey('meta', \$response, 'La zone meta est absente de la réponse');

        // Schema partiel
        \$this->assertZoneMatchesSchema(\$response['meta'], 'partials/meta');

        // Snapshot partiel (diff Git lisible indépendamment du contenu)
        \$this->assertPartialSnapshot(\$response['meta'], '${scenario}.meta');

        // Règles métier (title non vide, robots valide, canonical absolu, ogImage dans /fileadmin/)
        \$this->assertValidMetaZone(\$response['meta'], '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 4. Zone i18n
    // -----------------------------------------------------------------------

    /**
     * @test
     */
    public function i18nZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});

        \$this->assertArrayHasKey('i18n', \$response, 'La zone i18n est absente de la réponse');

        \$this->assertZoneMatchesSchema(\$response['i18n'], 'partials/i18n');
        \$this->assertPartialSnapshot(\$response['i18n'], '${scenario}.i18n');

        // Passer la locale attendue en 2ème argument si elle est fixe pour ce scénario
        // ex: \$this->assertValidI18nZone(\$response['i18n'], 'fr_FR.UTF-8', '${scenario}');
        \$this->assertValidI18nZone(\$response['i18n'], '', '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 5. Zone breadcrumbs
    // -----------------------------------------------------------------------

    /**
     * @test
     */
    public function breadcrumbsZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});

        \$this->assertArrayHasKey('breadcrumbs', \$response, 'La zone breadcrumbs est absente de la réponse');

        \$this->assertZoneMatchesSchema(\$response['breadcrumbs'], 'partials/breadcrumbs');
        \$this->assertPartialSnapshot(\$response['breadcrumbs'], '${scenario}.breadcrumbs');

        // Règles métier : racine = /, un seul current=true, dernier = current
        \$this->assertValidBreadcrumbsZone(\$response['breadcrumbs'], '${scenario}');
    }

    // -----------------------------------------------------------------------
    // 6. Zone appearance (layout backend)
    // -----------------------------------------------------------------------

    /**
     * @test
     */
    public function appearanceZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});

        \$this->assertArrayHasKey('appearance', \$response, 'La zone appearance est absente de la réponse');

        \$this->assertZoneMatchesSchema(\$response['appearance'], 'partials/appearance');
        \$this->assertPartialSnapshot(\$response['appearance'], '${scenario}.appearance');
    }

    // -----------------------------------------------------------------------
    // 7. Zone content (colPos)
    // -----------------------------------------------------------------------

    /**
     * @test
     */
    public function contentZoneMatchesSchemaAndSnapshot(): void
    {
        \$response = \$this->getHeadlessResponse(${page_uid});

        \$this->assertArrayHasKey('content', \$response, 'La zone content est absente de la réponse');

        \$this->assertZoneMatchesSchema(\$response['content'], 'partials/content');
        \$this->assertPartialSnapshot(\$response['content'], '${scenario}.content');

        // Vérifier que colPos0 est toujours présent (adapter si besoin: ['colPos0', 'colPos1'])
        \$this->assertValidContentZone(\$response['content'], ['colPos0']);
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