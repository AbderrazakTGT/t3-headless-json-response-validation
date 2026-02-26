#!/bin/bash
# =============================================================================
# front/scripts/validate-api.sh
# Validation légère de l'API depuis le frontend.
# Ne nécessite pas PHPUnit — utilise ajv-cli + les schemas versionnés.
#
# Usage :
#   ./front/scripts/validate-api.sh http://localhost:8080
#   ./front/scripts/validate-api.sh https://staging.monsite.com
# =============================================================================

BASE_URL=${1:-"http://localhost:8080"}
SCHEMA_DIR="../Tests/Fixtures/Schemas"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

echo "=========================================="
echo "🔍 VALIDATION API HEADLESS"
echo "=========================================="
echo -e "🌐 URL : ${YELLOW}$BASE_URL${NC}"
echo ""

# Vérifier que ajv-cli est installé
if ! npx ajv --version &> /dev/null 2>&1; then
    echo -e "${YELLOW}Installation de ajv-cli...${NC}"
    npm install -g ajv-cli ajv-formats
fi

# Vérifier que curl est disponible
if ! command -v curl &> /dev/null; then
    echo -e "${RED}❌ curl requis${NC}"
    exit 1
fi

# Correspondance scénario → page UID
declare -A SCENARIOS=(
    ["page_simple"]=1
    ["page_with_content"]=2
    ["page_with_images"]=3
    ["page_with_categories"]=4
)

for scenario in "${!SCENARIOS[@]}"; do
    uid=${SCENARIOS[$scenario]}
    schema="$SCHEMA_DIR/${scenario}.schema.json"

    echo -e "📄 ${YELLOW}$scenario${NC} (page $uid)"

    # Vérifier que le schema existe
    if [ ! -f "$schema" ]; then
        echo -e "   ${YELLOW}⚠${NC}  Schema introuvable : $schema (ignoré)"
        continue
    fi

    # Appel API
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/api/pages/$uid" 2>/dev/null)
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    if [ "$http_code" != "200" ]; then
        echo -e "   ${RED}✗${NC} HTTP $http_code — endpoint inaccessible"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Valider contre le schema
    echo "$body" > /tmp/api_response_${scenario}.json
    VALIDATION=$(echo "$body" | npx ajv validate -s "$schema" -d - 2>&1)

    if echo "$VALIDATION" | grep -q "valid"; then
        echo -e "   ${GREEN}✓${NC} Schema valide"
    else
        echo -e "   ${RED}✗${NC} Schema invalide :"
        echo "$VALIDATION" | sed 's/^/      /'
        FAILED=$((FAILED + 1))
    fi

    # Validation des zones critiques (sans schema)
    META_ROBOTS=$(echo "$body" | jq -r '.meta.robots // empty' 2>/dev/null)
    if [ -n "$META_ROBOTS" ]; then
        if echo "$META_ROBOTS" | grep -qE '^(index|noindex),(follow|nofollow)$'; then
            echo -e "   ${GREEN}✓${NC} meta.robots valide : $META_ROBOTS"
        else
            echo -e "   ${RED}✗${NC} meta.robots invalide : $META_ROBOTS"
            FAILED=$((FAILED + 1))
        fi
    fi

    BREADCRUMBS_COUNT=$(echo "$body" | jq '.breadcrumbs | length' 2>/dev/null)
    if [ -n "$BREADCRUMBS_COUNT" ] && [ "$BREADCRUMBS_COUNT" -gt 0 ]; then
        echo -e "   ${GREEN}✓${NC} breadcrumbs : $BREADCRUMBS_COUNT éléments"
    else
        echo -e "   ${YELLOW}⚠${NC}  breadcrumbs vide ou absent"
    fi

    rm -f /tmp/api_response_${scenario}.json
    echo ""
done

echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ TOUTES LES VALIDATIONS PASSENT${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAILED VALIDATION(S) ÉCHOUÉE(S)${NC}"
    exit 1
fi
echo "=========================================="
