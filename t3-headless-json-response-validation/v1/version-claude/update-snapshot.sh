#!/bin/bash
# Script de mise à jour des snapshots
#
# [CORRECTIF] Les snapshots sont maintenant générés via PHPUnit lui-même
# (UPDATE_SNAPSHOTS=1) et non plus via curl sur http://localhost.
# Cela garantit que les snapshots sont produits dans le même environnement
# que les tests et ne nécessitent pas de serveur web actif.

echo "=========================================="
echo "📸 MISE À JOUR DES SNAPSHOTS"
echo "=========================================="

PHPUNIT_CONFIG=${PHPUNIT_CONFIG:-"typo3/sysext/core/Build/FunctionalTests.xml"}
TEST_DIR="Tests/Functional/Headless"
SNAPSHOT_DIR="Tests/Fixtures/Snapshots"

# Vérifier que vendor/bin/phpunit est disponible
if ! command -v vendor/bin/phpunit &> /dev/null; then
    echo -e "${RED}❌ vendor/bin/phpunit introuvable. Lancez composer install d'abord.${NC}"
    exit 1
fi

# Vérifier que la config PHPUnit existe
if [ ! -f "$PHPUNIT_CONFIG" ]; then
    echo -e "${RED}❌ Configuration PHPUnit introuvable : $PHPUNIT_CONFIG${NC}"
    exit 1
fi

echo -e "📂 Config PHPUnit : $PHPUNIT_CONFIG"
echo -e "📂 Snapshots dans : $SNAPSHOT_DIR"
echo ""

# [CORRECTIF] Régénération via le Testing Framework TYPO3, pas via curl
echo -e "🔄 Lancement PHPUnit avec UPDATE_SNAPSHOTS=1..."
UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \
    -c "$PHPUNIT_CONFIG" \
    "$TEST_DIR" \
    --testdox

EXIT_CODE=$?

echo -e "\n=========================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ SNAPSHOTS MIS À JOUR${NC}"
else
    # markTestSkipped retourne exit code 0, une vraie erreur serait exit != 0
    echo -e "${YELLOW}⚠️  Vérifiez les résultats ci-dessus${NC}"
fi
echo "=========================================="
echo -e "N'oubliez pas de commiter les changements :"
echo -e "  git add $SNAPSHOT_DIR"
echo -e "  git commit -m \"Update JSON snapshots\""
echo "=========================================="
