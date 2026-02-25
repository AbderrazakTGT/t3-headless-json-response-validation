#!/bin/bash
# Script de mise à jour des snapshots

echo "=========================================="
echo "📸 MISE À JOUR DES SNAPSHOTS"
echo "=========================================="

BASE_URL=${1:-"http://localhost"}
SNAPSHOT_DIR="Tests/Fixtures/Snapshots"

# Vérifier que jq est installé
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq n'est pas installé. Installation: sudo apt-get install jq${NC}"
    exit 1
fi

# Définition des scénarios
declare -A SCENARIOS=(
    ["page_simple"]=1
    ["page_with_content"]=2
    ["page_with_images"]=3
    ["page_with_categories"]=4
)

# Mise à jour des snapshots
for scenario in "${!SCENARIOS[@]}"; do
    page_uid=${SCENARIOS[$scenario]}
    echo -e "\n📸 Mise à jour: ${YELLOW}$scenario${NC} (page $page_uid)"
    
    # Appel API avec formatage propre
    curl -s "$BASE_URL/api/pages/$page_uid" | jq '.' > "$SNAPSHOT_DIR/${scenario}.json"
    
    if [ $? -eq 0 ]; then
        echo -e "   ${GREEN}✓${NC} Snapshot mis à jour"
        
        # Vérification que le fichier n'est pas vide
        if [ ! -s "$SNAPSHOT_DIR/${scenario}.json" ]; then
            echo -e "   ${RED}✗${NC} Fichier vide - erreur API ?"
        fi
    else
        echo -e "   ${RED}✗${NC} Échec mise à jour"
    fi
done

echo -e "\n=========================================="
echo -e "${GREEN}✅ SNAPSHOTS MIS À JOUR${NC}"
echo "=========================================="
echo -e "N'oubliez pas de commiter les changements :"
echo -e "git add $SNAPSHOT_DIR"
echo -e "git commit -m \"Update JSON snapshots\""
echo "=========================================="