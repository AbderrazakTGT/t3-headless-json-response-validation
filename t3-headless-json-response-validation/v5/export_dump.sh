#!/bin/bash
# =============================================================================
# export_dump.sh
# Exporte la base EC2 de référence après cleanup.
# À exécuter sur l'instance EC2 de test, jamais en production.
#
# Ce script produit le dump qui sera commité dans tests/database/
# et partagé avec tous les développeurs et le CI.
#
# Usage (sur EC2) :
#   ./Tests/Scripts/export_dump.sh
#   ./Tests/Scripts/export_dump.sh --output /chemin/custom/dump.sql.gz
# =============================================================================

OUTPUT_FILE="tests/database/typo3_test.sql.gz"
EC2_DB_HOST="${DB_HOST:-127.0.0.1}"
EC2_DB_NAME="${DB_NAME:-typo3}"
EC2_DB_USER="${DB_USER:-typo3}"
EC2_DB_PASS="${DB_PASS:-}"

for arg in "$@"; do
    case $arg in
        --output=*) OUTPUT_FILE="${arg#*=}" ;;
    esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "📤 EXPORT BASE EC2 → DUMP DE RÉFÉRENCE"
echo "=========================================="
echo -e "${YELLOW}⚠️  À exécuter sur l'EC2 de test uniquement — jamais en production${NC}"
echo ""

mkdir -p "$(dirname "$OUTPUT_FILE")"

# Vérifier mysql disponible
if ! command -v mysqldump &> /dev/null; then
    echo -e "${RED}❌ mysqldump introuvable${NC}"
    exit 1
fi

echo "🔧 Export de la base $EC2_DB_NAME..."

# Tables à exclure de l'export (cache, sessions, logs)
EXCLUDE_TABLES=(
    "cache_hash"
    "cache_pages"
    "cache_pagesection"
    "cache_rootline"
    "cache_imagesizes"
    "cache_treelist"
    "cf_cache_hash"
    "cf_cache_hash_tags"
    "cf_cache_pages"
    "cf_cache_pages_tags"
    "cf_cache_rootline"
    "cf_cache_rootline_tags"
    "be_sessions"
    "fe_sessions"
    "sys_log"
    "sys_history"
)

IGNORE_ARGS=""
for table in "${EXCLUDE_TABLES[@]}"; do
    IGNORE_ARGS="$IGNORE_ARGS --ignore-table=$EC2_DB_NAME.$table"
done

# Export
if mysqldump \
    -h "$EC2_DB_HOST" \
    -u "$EC2_DB_USER" \
    ${EC2_DB_PASS:+-p"$EC2_DB_PASS"} \
    "$EC2_DB_NAME" \
    $IGNORE_ARGS \
    --single-transaction \
    --no-tablespaces \
    --set-gtid-purged=OFF \
    2>/dev/null | gzip -9 > "$OUTPUT_FILE"; then
    echo -e "${GREEN}✓${NC} Dump exporté : $OUTPUT_FILE"
    echo "   Taille : $(du -sh "$OUTPUT_FILE" | cut -f1)"
else
    echo -e "${RED}❌ Échec de l'export${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ EXPORT TERMINÉ${NC}"
echo "=========================================="
echo ""
echo "Prochaine étape (sur votre machine de dev) :"
echo "  git add tests/database/typo3_test.sql.gz"
echo "  git commit -m \"chore(db): update test database dump after [feature/cleanup]\""
echo "  git push origin main"
echo ""
echo "Les développeurs récupèrent la nouvelle base avec :"
echo "  git pull && ./Tests/Scripts/import_dump.sh"
echo "=========================================="
