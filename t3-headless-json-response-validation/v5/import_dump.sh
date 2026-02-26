#!/bin/bash
# =============================================================================
# import_dump.sh
# Importe la base de référence depuis tests/database/ dans l'environnement local.
#
# Ce dump est la SOURCE DE VÉRITÉ partagée entre :
#   - tous les développeurs
#   - le CI
#
# Après import, les données de la base EC2 de référence sont disponibles
# localement. Le développeur peut ensuite :
#   - ajouter ses données de feature dans le backend TYPO3 local
#   - générer ses snapshots locaux
#   - lancer les tests
#
# Usage :
#   ./Tests/Scripts/import_dump.sh              → import dans DDEV
#   ./Tests/Scripts/import_dump.sh --ci         → import dans le CI (MySQL direct)
# =============================================================================

DUMP_FILE="tests/database/typo3_test.sql.gz"
MODE="ddev"

for arg in "$@"; do
    case $arg in
        --ci) MODE="ci" ;;
    esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "📥 IMPORT DE LA BASE DE RÉFÉRENCE"
echo "=========================================="

# Vérifier que le dump existe
if [ ! -f "$DUMP_FILE" ]; then
    echo -e "${RED}❌ Dump introuvable : $DUMP_FILE${NC}"
    echo "   Vérifiez que le dépôt est à jour : git pull"
    exit 1
fi

DUMP_SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
echo -e "   Dump : ${YELLOW}$DUMP_FILE${NC} ($DUMP_SIZE)"
echo ""

if [ "$MODE" = "ddev" ]; then
    # ─── Import dans DDEV ────────────────────────────────────────────────────
    if ! command -v ddev &> /dev/null; then
        echo -e "${RED}❌ DDEV introuvable${NC}"
        exit 1
    fi
    if ! ddev status 2>/dev/null | grep -q "running"; then
        echo -e "${YELLOW}⚠️  DDEV non démarré — démarrage...${NC}"
        ddev start
    fi

    echo "🔧 Import dans DDEV..."
    DB_NAME=$(ddev status 2>/dev/null | grep "Database" | awk '{print $2}' || echo "db")

    if gunzip -c "$DUMP_FILE" | ddev mysql 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Base importée dans DDEV"
    else
        echo -e "${RED}❌ Échec de l'import${NC}"
        echo "   Essayez manuellement : gunzip -c $DUMP_FILE | ddev mysql"
        exit 1
    fi

elif [ "$MODE" = "ci" ]; then
    # ─── Import dans le CI (MySQL direct via variables d'environnement) ──────
    DB_HOST="${typo3DatabaseHost:-mysql}"
    DB_NAME="${typo3DatabaseName:-typo3_test}"
    DB_USER="${typo3DatabaseUsername:-root}"
    DB_PASS="${typo3DatabasePassword:-root}"

    echo "🔧 Import CI → mysql://$DB_HOST/$DB_NAME..."

    if gunzip -c "$DUMP_FILE" | mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Base importée dans le CI"
    else
        echo -e "${RED}❌ Échec de l'import CI${NC}"
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ BASE DE RÉFÉRENCE IMPORTÉE${NC}"
echo "=========================================="
echo ""
echo "Prochaines étapes :"
if [ "$MODE" = "ddev" ]; then
    echo "  1. Ajouter vos données de feature dans le backend TYPO3 local"
    echo "  2. UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ... (snapshots locaux)"
    echo "  3. vendor/bin/phpunit ... --testdox (tests)"
fi
echo "=========================================="
