#!/bin/bash
# =============================================================================
# generate_headless_tests.sh
# Génère les fichiers PHP de test (versionnés dans Git — aucune donnée).
# Inclut le scénario page_protected avec authentification FE user.
# =============================================================================

TEST_DIR="Tests/Functional/Headless"
FIXTURE_DIR="Tests/Fixtures"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🚀 GÉNÉRATION DES TESTS HEADLESS TYPO3 v13"
echo "=========================================="

mkdir -p "$TEST_DIR" "$FIXTURE_DIR/Database" "$FIXTURE_DIR/Schemas" "$FIXTURE_DIR/Snapshots"

# =============================================================================
# Génère un test PHPUnit standard (7 méthodes — pages publiques)
# =============================================================================
generate_test() {
    local scenario=$1
    local page_uid=$2
    local class_name=""

    IFS='_' read -ra parts <<< "$scenario"
    for part in "${parts[@]}"; do class_name+="${part^}"; done

    local test_file="$TEST_DIR/${class_name}Test.php"
    echo -e "\n📝 ${YELLOW}${class_name}Test.php${NC}"

    cat > "$test_file" << EOF
<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

/**
 * Tests JSON headless — scénario : ${scenario}
 *
 * ❌ Fixtures gitignorées — générer avec : ./Tests/Scripts/generate_fixtures.sh
 * ❌ Snapshots gitignorés — générer avec :
 *    UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless
 */
class ${class_name}Test extends AbstractHeadlessTestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        \$this->importScenarioFixtures('${scenario}');
    }

    /** @test */
    public function jsonResponseMatchesGlobalSchema(): void
    {
        \$this->assertMatchesJsonSchema(\$this->getHeadlessResponse(${page_uid}), '${scenario}');
    }

    /** @test */
    public function jsonResponseMatchesGlobalSnapshot(): void
    {
        \$this->assertMatchesSnapshot(\$this->getHeadlessResponseRaw(${page_uid}), '${scenario}');
    }

    /** @test */
    public function metaZoneMatchesSchemaAndSnapshot(): void
    {
        \$r = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('meta', \$r, 'Zone meta absente');
        \$this->assertZoneMatchesSchema(\$r['meta'], 'partials/meta');
        \$this->assertPartialSnapshot(\$r['meta'], '${scenario}.meta');
        \$this->assertValidMetaZone(\$r['meta'], '${scenario}');
    }

    /** @test */
    public function i18nZoneMatchesSchemaAndSnapshot(): void
    {
        \$r = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('i18n', \$r, 'Zone i18n absente');
        \$this->assertZoneMatchesSchema(\$r['i18n'], 'partials/i18n');
        \$this->assertPartialSnapshot(\$r['i18n'], '${scenario}.i18n');
        \$this->assertValidI18nZone(\$r['i18n'], '', '${scenario}');
    }

    /** @test */
    public function breadcrumbsZoneMatchesSchemaAndSnapshot(): void
    {
        \$r = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('breadcrumbs', \$r, 'Zone breadcrumbs absente');
        \$this->assertZoneMatchesSchema(\$r['breadcrumbs'], 'partials/breadcrumbs');
        \$this->assertPartialSnapshot(\$r['breadcrumbs'], '${scenario}.breadcrumbs');
        \$this->assertValidBreadcrumbsZone(\$r['breadcrumbs'], '${scenario}');
    }

    /** @test */
    public function appearanceZoneMatchesSchemaAndSnapshot(): void
    {
        \$r = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('appearance', \$r, 'Zone appearance absente');
        \$this->assertZoneMatchesSchema(\$r['appearance'], 'partials/appearance');
        \$this->assertPartialSnapshot(\$r['appearance'], '${scenario}.appearance');
    }

    /** @test */
    public function contentZoneMatchesSchemaAndSnapshot(): void
    {
        \$r = \$this->getHeadlessResponse(${page_uid});
        \$this->assertArrayHasKey('content', \$r, 'Zone content absente');
        \$this->assertZoneMatchesSchema(\$r['content'], 'partials/content');
        \$this->assertPartialSnapshot(\$r['content'], '${scenario}.content');
        \$this->assertValidContentZone(\$r['content'], ['colPos0']);
    }
}
EOF
    echo -e "${GREEN}✓${NC} $test_file"
}

# =============================================================================
# Génère le test pour la page protégée (avec méthodes d'authentification FE)
# FE users UIDs : 100=standard, 101=premium, 102=admin
# Mot de passe : "password" pour tous
# =============================================================================
generate_protected_test() {
    local scenario="page_protected"
    local page_uid=5
    local test_file="$TEST_DIR/PageProtectedTest.php"

    echo -e "\n📝 ${YELLOW}PageProtectedTest.php${NC} (avec authentification FE)"

    cat > "$test_file" << 'EOF'
<?php
declare(strict_types=1);

namespace MyVendor\MyExtension\Tests\Functional\Headless;

/**
 * Tests JSON headless — scénario : page_protected
 *
 * Valide l'authentification FE et les droits d'accès.
 * FE users de test (uid → rôle → mot de passe) :
 *   100 → standard → "password"
 *   101 → premium  → "password"
 *   102 → admin    → "password"
 *
 * ❌ Fixtures gitignorées — générer avec : ./Tests/Scripts/generate_fixtures.sh
 */
class PageProtectedTest extends AbstractHeadlessTestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->importScenarioFixtures('page_protected');
    }

    // -----------------------------------------------------------------------
    // Contrôle d'accès
    // -----------------------------------------------------------------------

    /**
     * @test
     * Un accès non authentifié doit être refusé (302 ou 403).
     */
    public function unauthenticatedAccessIsDenied(): void
    {
        $this->assertUnauthenticatedAccessDenied(5);
    }

    /**
     * @test
     * L'utilisateur standard (uid=100) appartient au groupe fe_group=1.
     * La page a fe_group=1 → accès autorisé.
     */
    public function standardUserCanAccessProtectedPage(): void
    {
        $response = $this->getHeadlessResponseAsFeUser(5, 100);

        $this->assertArrayHasKey('content', $response, 'Zone content absente');
        $this->assertValidContentZone($response['content'], ['colPos0']);

        // Le contenu principal est accessible
        $elements = $response['content']['colPos0'] ?? [];
        $this->assertNotEmpty($elements, 'Aucun élément de contenu pour le standard user');
    }

    /**
     * @test
     * L'utilisateur premium (uid=101) appartient aux groupes 1+2.
     * Il doit voir le même contenu que le standard + contenu premium.
     */
    public function premiumUserSeesFullContent(): void
    {
        $responseStandard = $this->getHeadlessResponseAsFeUser(5, 100);
        $responsePremium  = $this->getHeadlessResponseAsFeUser(5, 101);

        $countStandard = count($responseStandard['content']['colPos0'] ?? []);
        $countPremium  = count($responsePremium['content']['colPos0'] ?? []);

        // Le premium voit au moins autant d'éléments que le standard
        $this->assertGreaterThanOrEqual(
            $countStandard,
            $countPremium,
            'Le premium user devrait voir au moins autant de contenu que le standard user'
        );
    }

    /**
     * @test
     * L'utilisateur admin (uid=102) doit avoir un accès complet.
     */
    public function adminUserCanAccessProtectedPage(): void
    {
        $response = $this->getHeadlessResponseAsFeUser(5, 102);
        $this->assertMatchesJsonSchema($response, 'page_protected');
    }

    // -----------------------------------------------------------------------
    // Validation complète (identique aux autres scénarios, authentifié)
    // -----------------------------------------------------------------------

    /** @test */
    public function jsonResponseMatchesGlobalSchemaAsStandardUser(): void
    {
        $this->assertMatchesJsonSchema(
            $this->getHeadlessResponseAsFeUser(5, 100),
            'page_protected'
        );
    }

    /** @test */
    public function jsonResponseMatchesGlobalSnapshotAsStandardUser(): void
    {
        $request = (new \TYPO3\TestingFramework\Core\Functional\Framework\Frontend\InternalRequest('https://website.local/'))
            ->withQueryParameter('id', 5);
        $context = (new \TYPO3\TestingFramework\Core\Functional\Framework\Frontend\InternalRequestContext())
            ->withFrontendUserId(100);
        $raw = (string)$this->executeFrontendSubRequest($request, $context)->getBody();
        $this->assertMatchesSnapshot($raw, 'page_protected');
    }

    /** @test */
    public function metaZoneMatchesSchemaAndSnapshot(): void
    {
        $r = $this->getHeadlessResponseAsFeUser(5, 100);
        $this->assertArrayHasKey('meta', $r);
        $this->assertZoneMatchesSchema($r['meta'], 'partials/meta');
        $this->assertPartialSnapshot($r['meta'], 'page_protected.meta');
        $this->assertValidMetaZone($r['meta'], 'page_protected');
    }

    /** @test */
    public function breadcrumbsZoneMatchesSchemaAndSnapshot(): void
    {
        $r = $this->getHeadlessResponseAsFeUser(5, 100);
        $this->assertArrayHasKey('breadcrumbs', $r);
        $this->assertZoneMatchesSchema($r['breadcrumbs'], 'partials/breadcrumbs');
        $this->assertPartialSnapshot($r['breadcrumbs'], 'page_protected.breadcrumbs');
        $this->assertValidBreadcrumbsZone($r['breadcrumbs'], 'page_protected');
    }
}
EOF
    echo -e "${GREEN}✓${NC} $test_file"
}

# =============================================================================
# Génération
# =============================================================================
echo -e "\n=========================================="
echo "🏗️  GÉNÉRATION DES SCÉNARIOS"
echo "=========================================="

generate_test "page_simple"          1
generate_test "page_with_content"    2
generate_test "page_with_images"     3
generate_test "page_with_categories" 4
generate_protected_test

echo -e "\n=========================================="
echo -e "${GREEN}✅ TESTS PHP GÉNÉRÉS (dans Git — aucune donnée)${NC}"
echo "=========================================="
echo -e "📁 Tests : ${YELLOW}$TEST_DIR${NC}"
echo ""
echo "Prochaines étapes :"
echo "  1. ./Tests/Scripts/generate_fixtures.sh   (fixtures locales gitignorées)"
echo "  2. UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ... (snapshots locaux)"
echo "  3. vendor/bin/phpunit ...                   (vérification)"
echo "=========================================="
