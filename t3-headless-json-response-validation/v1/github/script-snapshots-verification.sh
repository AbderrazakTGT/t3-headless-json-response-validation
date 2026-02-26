#!/bin/bash
# Script de vérification des snapshots

echo "=========================================="
echo "🔍 VÉRIFICATION DES SNAPSHOTS"
echo "=========================================="

SNAPSHOT_DIR="Tests/Fixtures/Snapshots"
FAILED=0
WARNINGS=0

# Vérifier que le dossier existe
if [ ! -d "$SNAPSHOT_DIR" ]; then
    echo -e "${RED}❌ Dossier $SNAPSHOT_DIR introuvable${NC}"
    exit 1
fi

# Compter les snapshots
COUNT=$(ls -1 "$SNAPSHOT_DIR"/*.json 2>/dev/null | wc -l)
if [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}❌ Aucun snapshot trouvé${NC}"
    exit 1
fi

echo -e "📊 Snapshots trouvés: $COUNT\n"

# Vérification de chaque snapshot
for snapshot in "$SNAPSHOT_DIR"/*.json; do
    filename=$(basename "$snapshot")
    echo -e "📄 Vérification: ${YELLOW}$filename${NC}"
    
    # 1. Validation JSON
    if jq empty "$snapshot" 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} JSON valide"
    else
        echo -e "   ${RED}✗${NC} JSON invalide"
        FAILED=1
        continue
    fi
    
    # 2. Vérification des UIDs (doivent être stables: 1-5)
    uids=$(jq '[.. | .uid? // empty] | unique | sort[]' "$snapshot" 2>/dev/null)
    for uid in $uids; do
        if [ "$uid" -gt 5 ]; then
            echo -e "   ${YELLOW}⚠${NC} UID non standard détecté: $uid"
            WARNINGS=$((WARNINGS + 1))
        fi
    done
    
    # 3. Vérification des champs dynamiques
    if jq '.. | .crdate? // .tstamp? // .lastUpdated? // empty' "$snapshot" 2>/dev/null | grep -q .; then
        echo -e "   ${YELLOW}⚠${NC} Champs dynamiques détectés (crdate/tstamp/lastUpdated)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "   ${GREEN}✓${NC} Pas de champs dynamiques"
    fi
    
    echo ""
done

# Résumé
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✅ TOUS LES SNAPSHOTS SONT VALIDES${NC}"
    else
        echo -e "${YELLOW}⚠️  SNAPSHOTS VALIDES AVEC $WARNINGS AVERTISSEMENT(S)${NC}"
    fi
    exit 0
else
    echo -e "${RED}❌ DES ERREURS ONT ÉTÉ DÉTECTÉES${NC}"
    exit 1
fi
echo "=========================================="