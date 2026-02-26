#!/bin/bash
# =============================================================================
# update_snapshots.sh
# Régénère les snapshots JSON via PHPUnit (jamais via curl).
#
# ⚠️  SÉCURITÉ : les snapshots sont gitignorés — ne jamais les commiter.
#     Ils sont régénérés localement par chaque développeur
#     et dans le CI comme artifact éphémère.
# =============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "📸 MISE À JOUR DES SNAPSHOTS"
echo "=========================================="
echo -e "${YELLOW}⚠️  Les snapshots sont gitignorés — ne jamais les commiter${NC}"
echo ""

PHPUNIT_CONFIG=${PHPUNIT_CONFIG:-"typo3/sysext/core/Build/FunctionalTests.xml"}
TEST_DIR="Tests/Functional/Headless"
SNAPSHOT_DIR="Tests/Fixtures/Snapshots"
FIXTURE_DIR="Tests/Fixtures/Database"

# Vérifier que les fixtures existent
if [ ! -d "$FIXTURE_DIR" ] || [ -z "$(ls -A $FIXTURE_DIR 2>/dev/null)" ]; then
    echo -e "${RED}❌ Fixtures CSV introuvables dans $FIXTURE_DIR${NC}"
    echo "   Générez-les d'abord :"
    echo "   ./Tests/Scripts/generate_fixtures.sh"
    exit 1
fi

# Vérifier PHPUnit
if ! [ -f "vendor/bin/phpunit" ]; then
    echo -e "${RED}❌ vendor/bin/phpunit introuvable. Lancez : composer install${NC}"
    exit 1
fi

# Vérifier la config PHPUnit
if [ ! -f "$PHPUNIT_CONFIG" ]; then
    echo -e "${RED}❌ Config PHPUnit introuvable : $PHPUNIT_CONFIG${NC}"
    exit 1
fi

echo -e "📂 Config  : $PHPUNIT_CONFIG"
echo -e "📂 Snapshots : $SNAPSHOT_DIR"
echo ""
echo -e "🔄 Génération via PHPUnit (UPDATE_SNAPSHOTS=1)..."
echo ""

UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
    -c "$PHPUNIT_CONFIG" \
    "$TEST_DIR" \
    --testdox

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ SNAPSHOTS GÉNÉRÉS${NC}"
    echo ""
    # Compter les snapshots créés
    COUNT=$(find "$SNAPSHOT_DIR" -name "*.json" 2>/dev/null | wc -l)
    echo -e "   $COUNT fichiers dans $SNAPSHOT_DIR"
    echo ""
    echo -e "${YELLOW}⚠️  Ces fichiers sont gitignorés — ne PAS faire git add Snapshots/${NC}"
else
    echo -e "${YELLOW}⚠️  Vérifiez les erreurs ci-dessus${NC}"
fi
echo "=========================================="
