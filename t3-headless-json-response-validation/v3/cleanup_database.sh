#!/bin/bash
# =============================================================================
# cleanup_database.sh
# Nettoie la base DDEV locale AVANT extraction des fixtures.
#
# Résout les deux problèmes spécifiques à TYPO3 :
#   1. Soft-deletes : des milliers d'enregistrements marqués deleted=1
#      polluent les requêtes et gonflent les exports
#   2. Relations orphelines : sys_file_reference sans tt_content valide, etc.
#
# Utilise les commandes natives TYPO3 (cleanup:deletedrecords, etc.)
# avec fallback SQL si la commande n'est pas disponible.
#
# ⚠️  UNIQUEMENT sur la base DDEV locale — jamais en production.
#
# Usage :
#   ./Tests/Scripts/cleanup_database.sh
#   ./Tests/Scripts/cleanup_database.sh --min-age=7
#   ./Tests/Scripts/cleanup_database.sh --dry-run
# =============================================================================

MIN_AGE=30
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --min-age=*) MIN_AGE="${arg#*=}" ;;
        --dry-run)   DRY_RUN=true ;;
    esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🧹 NETTOYAGE SOFT-DELETES — BASE DDEV"
echo "=========================================="
echo -e "${YELLOW}⚠️  Base DDEV locale uniquement — jamais en production${NC}"
[ "$DRY_RUN" = true ] && echo -e "${BLUE}ℹ️  Mode --dry-run actif (simulation)${NC}"
echo -e "   Age minimum pour purge : ${MIN_AGE} jours"
echo ""

# Vérifier DDEV
if ! command -v ddev &> /dev/null; then
    echo -e "${RED}❌ DDEV introuvable${NC}"
    exit 1
fi
if ! ddev status 2>/dev/null | grep -q "running"; then
    echo -e "${RED}❌ DDEV non démarré. Lancez : ddev start${NC}"
    exit 1
fi

# =============================================================================
# Statistiques avant
# =============================================================================
echo -e "${BLUE}📊 Enregistrements deleted=1 avant nettoyage${NC}"
for table in pages tt_content sys_category sys_file_reference fe_users; do
    COUNT=$(ddev mysql -e "SELECT COUNT(*) FROM $table WHERE deleted=1" \
        --batch --skip-column-names 2>/dev/null | tr -d '\n')
    echo -e "   $table : ${YELLOW}${COUNT:-0}${NC}"
done
echo ""

[ "$DRY_RUN" = true ] && { echo -e "${BLUE}Dry-run — aucune modification.${NC}"; exit 0; }

# =============================================================================
# Étape 1 — Commandes natives TYPO3
# =============================================================================
echo -e "${BLUE}🔧 Commandes TYPO3 natives${NC}"

echo -n "   cleanup:deletedrecords --min-age=$MIN_AGE ... "
ddev exec vendor/bin/typo3 cleanup:deletedrecords --min-age="$MIN_AGE" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}non disponible → fallback SQL${NC}"
    CUTOFF=$(date -d "$MIN_AGE days ago" +%s 2>/dev/null || \
             date -v -${MIN_AGE}d +%s 2>/dev/null || \
             echo $(($(date +%s) - MIN_AGE * 86400)))
    for table in pages tt_content sys_category sys_file_reference; do
        ddev mysql -e "DELETE FROM $table WHERE deleted=1 AND tstamp < $CUTOFF" 2>/dev/null
    done
    echo -e "   ${GREEN}✓${NC} Suppression SQL (cutoff: $CUTOFF)"
fi

echo -n "   cleanup:missingrelations --update-refindex ... "
ddev exec vendor/bin/typo3 cleanup:missingrelations --update-refindex > /dev/null 2>&1
[ $? -eq 0 ] && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}ignoré${NC}"

echo -n "   referenceindex:update ... "
ddev exec vendor/bin/typo3 referenceindex:update > /dev/null 2>&1
[ $? -eq 0 ] && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}ignoré${NC}"

# =============================================================================
# Étape 2 — Nettoyage SQL complémentaire
# =============================================================================
echo ""
echo -e "${BLUE}🔧 Nettoyage SQL complémentaire${NC}"

ddev mysql -e "DELETE FROM fe_users WHERE deleted=1" 2>/dev/null
echo -e "   ${GREEN}✓${NC} fe_users deleted=1"

ddev mysql -e "DELETE FROM fe_sessions WHERE ses_tstamp < UNIX_TIMESTAMP() - 86400" 2>/dev/null
echo -e "   ${GREEN}✓${NC} fe_sessions expirées"

ddev mysql -e "DELETE FROM sys_log WHERE tstamp < UNIX_TIMESTAMP() - 2592000" 2>/dev/null
echo -e "   ${GREEN}✓${NC} sys_log > 30j"

# Vider les tables de cache
for cache_table in $(ddev mysql -e "SHOW TABLES LIKE 'cache_%'" --batch --skip-column-names 2>/dev/null); do
    ddev mysql -e "TRUNCATE TABLE \`$cache_table\`" 2>/dev/null
done
echo -e "   ${GREEN}✓${NC} Tables cache vidées"

# =============================================================================
# Statistiques après
# =============================================================================
echo ""
echo -e "${BLUE}📊 Enregistrements deleted=1 après nettoyage${NC}"
for table in pages tt_content sys_category; do
    COUNT=$(ddev mysql -e "SELECT COUNT(*) FROM $table WHERE deleted=1" \
        --batch --skip-column-names 2>/dev/null | tr -d '\n')
    echo -e "   $table : ${COUNT:-0}"
done

echo ""
echo "=========================================="
echo -e "${GREEN}✅ BASE NETTOYÉE${NC}"
echo "=========================================="
echo "Lancez maintenant :"
echo "  ./Tests/Scripts/extract_and_anonymize.sh [uid_simple] [uid_content] [uid_images] [uid_categories] [uid_protected]"
echo "=========================================="
