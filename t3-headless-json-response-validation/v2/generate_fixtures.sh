#!/bin/bash
# =============================================================================
# generate_fixtures.sh
# Génère les fixtures CSV synthétiques et anonymisées pour les tests PHPUnit.
#
# ⚠️  SÉCURITÉ : ce script ne touche JAMAIS à la base de production.
#     Les données sont entièrement fictives mais structurellement réalistes.
#     Les fichiers générés sont dans Tests/Fixtures/Database/ — gitignored.
#
# Usage :
#   ./Tests/Scripts/generate_fixtures.sh
# =============================================================================

FIXTURE_DIR="Tests/Fixtures/Database"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🏗️  GÉNÉRATION DES FIXTURES SYNTHÉTIQUES"
echo "=========================================="
echo -e "${YELLOW}⚠️  Données fictives — aucun accès base de production${NC}"
echo ""

mkdir -p \
  "$FIXTURE_DIR/page_simple" \
  "$FIXTURE_DIR/page_with_content" \
  "$FIXTURE_DIR/page_with_images" \
  "$FIXTURE_DIR/page_with_categories"

# =============================================================================
# SCÉNARIO 1 — Page simple
# =============================================================================
echo "📄 Scénario 1 : page_simple"

cat > "$FIXTURE_DIR/page_simple/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg
1,0,"Test Page Simple","/test-page-simple",1,0,0,1,0
CSV
echo -e "  ${GREEN}✓${NC} pages.csv"

# =============================================================================
# SCÉNARIO 2 — Page avec contenu texte
# =============================================================================
echo "📄 Scénario 2 : page_with_content"

cat > "$FIXTURE_DIR/page_with_content/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg,description,no_search
2,0,"Test Page With Content","/test-page-with-content",1,0,0,1,0,"Test meta description for page with content",0
CSV
echo -e "  ${GREEN}✓${NC} pages.csv"

cat > "$FIXTURE_DIR/page_with_content/tt_content.csv" << 'CSV'
uid,pid,header,bodytext,CType,colPos,sorting,hidden,header_layout
10,2,"Test Introduction","Lorem ipsum dolor sit amet consectetur adipiscing elit","text",0,1,0,2
11,2,"Test Section Two","Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua","text",0,2,0,2
12,2,"Test Section Three","Ut enim ad minim veniam quis nostrud exercitation ullamco","text",0,3,0,2
CSV
echo -e "  ${GREEN}✓${NC} tt_content.csv"

# =============================================================================
# SCÉNARIO 3 — Page avec images
# =============================================================================
echo "📄 Scénario 3 : page_with_images"

cat > "$FIXTURE_DIR/page_with_images/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg
3,0,"Test Page With Images","/test-page-with-images",1,0,0,1,0
CSV
echo -e "  ${GREEN}✓${NC} pages.csv"

cat > "$FIXTURE_DIR/page_with_images/tt_content.csv" << 'CSV'
uid,pid,header,bodytext,CType,colPos,sorting,hidden,image
20,3,"Test Image Section","Lorem ipsum with image","textpic",0,1,0,1
CSV
echo -e "  ${GREEN}✓${NC} tt_content.csv"

cat > "$FIXTURE_DIR/page_with_images/sys_file.csv" << 'CSV'
uid,pid,identifier,name,extension,mime_type,size,missing
1,0,"/fileadmin/test-images/test-image-1.jpg","test-image-1.jpg","jpg","image/jpeg",12345,0
CSV
echo -e "  ${GREEN}✓${NC} sys_file.csv"

cat > "$FIXTURE_DIR/page_with_images/sys_file_reference.csv" << 'CSV'
uid,pid,uid_local,uid_foreign,tablenames,fieldname,sorting,hidden,title,description,alternative
1,0,1,20,"tt_content","image",1,0,"Test image title","Test image description","Test alt text"
CSV
echo -e "  ${GREEN}✓${NC} sys_file_reference.csv"

# =============================================================================
# SCÉNARIO 4 — Page avec catégories
# =============================================================================
echo "📄 Scénario 4 : page_with_categories"

cat > "$FIXTURE_DIR/page_with_categories/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg
4,0,"Test Page With Categories","/test-page-with-categories",1,0,0,1,0
CSV
echo -e "  ${GREEN}✓${NC} pages.csv"

cat > "$FIXTURE_DIR/page_with_categories/tt_content.csv" << 'CSV'
uid,pid,header,bodytext,CType,colPos,sorting,hidden
30,4,"Test Categorized Content","Lorem ipsum categorized content","text",0,1,0
CSV
echo -e "  ${GREEN}✓${NC} tt_content.csv"

cat > "$FIXTURE_DIR/page_with_categories/sys_category.csv" << 'CSV'
uid,pid,title,description,hidden,deleted
1,0,"Test Category A","Description of test category A",0,0
2,0,"Test Category B","Description of test category B",0,0
CSV
echo -e "  ${GREEN}✓${NC} sys_category.csv"

cat > "$FIXTURE_DIR/page_with_categories/sys_category_record_mm.csv" << 'CSV'
uid_local,uid_foreign,tablenames,fieldname,sorting
30,1,"tt_content","categories",1
30,2,"tt_content","categories",2
CSV
echo -e "  ${GREEN}✓${NC} sys_category_record_mm.csv"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ FIXTURES GÉNÉRÉES${NC}"
echo "=========================================="
echo -e "📁 Dossier : ${YELLOW}$FIXTURE_DIR${NC}"
echo ""
echo "Ces fichiers sont gitignorés."
echo "Lancez UPDATE_SNAPSHOTS=1 vendor/bin/phpunit pour générer les snapshots."
echo "=========================================="
