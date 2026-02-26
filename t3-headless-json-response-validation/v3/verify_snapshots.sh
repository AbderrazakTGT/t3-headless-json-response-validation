#!/bin/bash
# =============================================================================
# verify_snapshots.sh
# Vérifie l'intégrité des snapshots locaux avant de lancer les tests complets.
# Rapide (~5s) — utilisé en premier dans le pipeline CI.
# =============================================================================

SNAPSHOT_DIR="Tests/Fixtures/Snapshots"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0
WARNINGS=0

echo "=========================================="
echo "🔍 VÉRIFICATION DES SNAPSHOTS"
echo "=========================================="

if [ ! -d "$SNAPSHOT_DIR" ]; then
    echo -e "${RED}❌ Dossier $SNAPSHOT_DIR introuvable${NC}"
    echo "   Générez les snapshots : ./Tests/Scripts/update_snapshots.sh"
    exit 1
fi

COUNT=$(find "$SNAPSHOT_DIR" -name "*.json" 2>/dev/null | wc -l)
if [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}❌ Aucun snapshot trouvé dans $SNAPSHOT_DIR${NC}"
    echo "   Générez-les : UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
    exit 1
fi

echo -e "📊 Snapshots trouvés : $COUNT"
echo ""

for snapshot in "$SNAPSHOT_DIR"/*.json; do
    [ -f "$snapshot" ] || continue
    filename=$(basename "$snapshot")

    echo -e "📄 ${YELLOW}$filename${NC}"

    # 1. JSON valide
    if jq empty "$snapshot" 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} JSON valide"
    else
        echo -e "   ${RED}✗${NC} JSON invalide"
        FAILED=$((FAILED + 1))
        continue
    fi

    # 2. Pas de champs dynamiques
    DYNAMIC=$(jq '[.. | objects | to_entries[] | select(.key | test("^(crdate|tstamp|lastUpdated)$")) | .key] | unique | .[]' "$snapshot" 2>/dev/null)
    if [ -n "$DYNAMIC" ]; then
        echo -e "   ${YELLOW}⚠${NC}  Champs dynamiques : $DYNAMIC"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "   ${GREEN}✓${NC} Pas de champs dynamiques"
    fi

    # 3. Pas d'email réel (pattern de sécurité)
    EMAILS=$(grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$snapshot" 2>/dev/null | grep -v "@example\.com" || true)
    if [ -n "$EMAILS" ]; then
        echo -e "   ${RED}✗${NC} Emails potentiellement réels détectés — vérifiez l'anonymisation"
        FAILED=$((FAILED + 1))
    else
        echo -e "   ${GREEN}✓${NC} Pas d'email réel détecté"
    fi

    # 4. Zones attendues présentes (pour les snapshots globaux)
    if [[ "$filename" != *"."*"."* ]]; then  # snapshot global (pas de point dans le nom de zone)
        for zone in meta i18n breadcrumbs appearance content; do
            if jq -e ".$zone" "$snapshot" > /dev/null 2>&1; then
                echo -e "   ${GREEN}✓${NC} Zone $zone présente"
            else
                echo -e "   ${YELLOW}⚠${NC}  Zone $zone absente"
                WARNINGS=$((WARNINGS + 1))
            fi
        done
    fi

    echo ""
done

echo "=========================================="
if [ $FAILED -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ TOUS LES SNAPSHOTS SONT VALIDES${NC}"
    exit 0
elif [ $FAILED -eq 0 ]; then
    echo -e "${YELLOW}⚠️  VALIDES AVEC $WARNINGS AVERTISSEMENT(S)${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED ERREUR(S) DÉTECTÉE(S)${NC}"
    exit 1
fi
echo "=========================================="
