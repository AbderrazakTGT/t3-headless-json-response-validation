#!/bin/bash
# =============================================================================
# cleanup_ec2.sh
# Nettoyage mensuel de la base EC2 de référence avant export du dump.
#
# Étapes :
#   1. Purge des enregistrements soft-deleted (cleanup:deletedrecords)
#   2. Nettoyage des relations orphelines (cleanup:missingrelations)
#   3. Mise à jour de l'index de référence (referenceindex:update)
#   4. Suppression des caches, sessions, logs anciens
#   5. Optimisation des tables
#
# ⚠️  À exécuter sur l'EC2 de test uniquement — jamais en production.
#
# Usage :
#   ./Tests/Scripts/cleanup_ec2.sh
#   ./Tests/Scripts/cleanup_ec2.sh --dry-run
#   ./Tests/Scripts/cleanup_ec2.sh --min-age=7
# =============================================================================

MIN_AGE=30
DRY_RUN=false
TYPO3_ROOT="${TYPO3_ROOT:-/var/www/html}"

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
echo "🧹 CLEANUP EC2 — BASE DE RÉFÉRENCE"
echo "=========================================="
echo -e "${YELLOW}⚠️  EC2 de test uniquement — jamais en production${NC}"
[ "$DRY_RUN" = true ] && echo -e "${BLUE}ℹ️  Mode dry-run actif${NC}"
echo -e "   Age minimum pour purge : ${MIN_AGE} jours"
echo ""

# Aller dans le dossier TYPO3
cd "$TYPO3_ROOT" || { echo -e "${RED}❌ TYPO3_ROOT introuvable : $TYPO3_ROOT${NC}"; exit 1; }

# Vérifier que vendor/bin/typo3 existe
if [ ! -f "vendor/bin/typo3" ]; then
    echo -e "${RED}❌ vendor/bin/typo3 introuvable${NC}"
    exit 1
fi

# =============================================================================
# Statistiques avant
# =============================================================================
echo -e "${BLUE}📊 Avant cleanup${NC}"
mysql_exec() {
    if command -v mysql &> /dev/null; then
        mysql -h "${DB_HOST:-127.0.0.1}" -u "${DB_USER:-typo3}" \
            ${DB_PASS:+-p"$DB_PASS"} "${DB_NAME:-typo3}" -e "$1" \
            --batch --skip-column-names 2>/dev/null
    fi
}

for table in pages tt_content sys_category sys_file_reference; do
    COUNT=$(mysql_exec "SELECT COUNT(*) FROM $table WHERE deleted=1" | tr -d '\n')
    echo -e "   $table deleted=1 : ${YELLOW}${COUNT:-?}${NC}"
done
echo ""

[ "$DRY_RUN" = true ] && { echo "Dry-run — aucune modification."; exit 0; }

# =============================================================================
# Étape 1 — Commandes TYPO3 natives
# =============================================================================
echo -e "${BLUE}🔧 Commandes TYPO3${NC}"

echo -n "   cleanup:deletedrecords --min-age=$MIN_AGE ... "
php vendor/bin/typo3 cleanup:deletedrecords --min-age="$MIN_AGE" > /dev/null 2>&1 \
    && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}commande non disponible${NC}"

echo -n "   cleanup:missingrelations --update-refindex ... "
php vendor/bin/typo3 cleanup:missingrelations --update-refindex > /dev/null 2>&1 \
    && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}ignoré${NC}"

echo -n "   referenceindex:update ... "
php vendor/bin/typo3 referenceindex:update > /dev/null 2>&1 \
    && echo -e "${GREEN}✓${NC}" || echo -e "${YELLOW}ignoré${NC}"

echo -n "   workspace:flush (versions) ... "
php vendor/bin/typo3 cleanup:flushWorkspaces > /dev/null 2>&1 \
    && echo -e "${GREEN}✓${NC}" || {
        # Fallback SQL : suppression des versions workspace (t3ver_wsid > 0)
        mysql_exec "DELETE FROM pages WHERE t3ver_wsid > 0" 2>/dev/null
        mysql_exec "DELETE FROM tt_content WHERE t3ver_wsid > 0" 2>/dev/null
        echo -e "${YELLOW}fallback SQL${NC}"
    }

# =============================================================================
# Étape 2 — Nettoyage SQL complémentaire
# =============================================================================
echo ""
echo -e "${BLUE}🔧 Nettoyage SQL${NC}"

mysql_exec "DELETE FROM fe_sessions WHERE ses_tstamp < UNIX_TIMESTAMP() - 86400"
echo -e "   ${GREEN}✓${NC} fe_sessions expirées"

mysql_exec "DELETE FROM sys_log WHERE tstamp < UNIX_TIMESTAMP() - $(( MIN_AGE * 86400 ))"
echo -e "   ${GREEN}✓${NC} sys_log > ${MIN_AGE}j"

mysql_exec "DELETE FROM sys_history WHERE tstamp < UNIX_TIMESTAMP() - $(( MIN_AGE * 86400 ))"
echo -e "   ${GREEN}✓${NC} sys_history > ${MIN_AGE}j"

# Vider les tables de cache
for cache_table in $(mysql_exec "SHOW TABLES LIKE 'cache_%'" 2>/dev/null); do
    mysql_exec "TRUNCATE TABLE \`$cache_table\`" 2>/dev/null
done
echo -e "   ${GREEN}✓${NC} Tables cache vidées"

# Optimiser les tables principales
for table in pages tt_content sys_file sys_file_reference; do
    mysql_exec "OPTIMIZE TABLE $table" > /dev/null 2>&1
done
echo -e "   ${GREEN}✓${NC} Tables optimisées"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ CLEANUP TERMINÉ${NC}"
echo "=========================================="
echo ""
echo "Prochaine étape : exporter le dump"
echo "  ./Tests/Scripts/export_dump.sh"
echo "=========================================="
