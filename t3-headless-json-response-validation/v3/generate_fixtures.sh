#!/bin/bash
# =============================================================================
# generate_fixtures.sh
# Génère des fixtures CSV synthétiques et anonymisées.
#
# ✅ Données fictives — aucun accès base de production requis
# ✅ Travail hors-ligne possible (CI, TGV, avion)
# ✅ deleted=0 partout — pas de soft-deletes
# ✅ FE users de test avec 3 rôles (standard, premium, admin)
# ✅ ~5 Ko par scénario (vs 1,3 Go en production)
#
# Usage : ./Tests/Scripts/generate_fixtures.sh
# =============================================================================

FIXTURE_DIR="Tests/Fixtures/Database"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🏗️  FIXTURES SYNTHÉTIQUES TYPO3 HEADLESS"
echo "=========================================="
echo -e "${YELLOW}⚠️  Données fictives — deleted=0 partout — aucune donnée réelle${NC}"
echo ""

mkdir -p \
  "$FIXTURE_DIR/shared" \
  "$FIXTURE_DIR/page_simple" \
  "$FIXTURE_DIR/page_with_content" \
  "$FIXTURE_DIR/page_with_images" \
  "$FIXTURE_DIR/page_with_categories" \
  "$FIXTURE_DIR/page_protected"

# =============================================================================
# SHARED — FE groups + FE users (utilisés par page_protected)
# 3 rôles : standard (uid=1), premium (uid=2), admin (uid=3)
# Mot de passe "password" pour tous (hash bcrypt TYPO3)
# =============================================================================
echo "👥 Fixtures partagées"

cat > "$FIXTURE_DIR/shared/fe_groups.csv" << 'CSV'
uid,pid,title,description,hidden,deleted,crdate,tstamp
1,0,"test_standard_group","Groupe utilisateurs standard",0,0,0,0
2,0,"test_premium_group","Groupe utilisateurs premium",0,0,0,0
3,0,"test_admin_group","Groupe administrateurs frontend",0,0,0,0
CSV
echo -e "  ${GREEN}✓${NC} shared/fe_groups.csv"

# Hash bcrypt de "password" compatible TYPO3 v13
HASH='$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'
cat > "$FIXTURE_DIR/shared/fe_users.csv" << CSV
uid,pid,username,password,usergroup,name,first_name,last_name,email,telephone,address,zip,city,country,hidden,deleted,disable,crdate,tstamp,lastlogin
100,0,"test_standard","$HASH","1","Test Standard User","Test","Standard","test-standard@example.com","","","","","",0,0,0,0,0,0
101,0,"test_premium","$HASH","1,2","Test Premium User","Test","Premium","test-premium@example.com","","","","","",0,0,0,0,0,0
102,0,"test_admin","$HASH","1,2,3","Test Admin User","Test","Admin","test-admin@example.com","","","","","",0,0,0,0,0,0
CSV
echo -e "  ${GREEN}✓${NC} shared/fe_users.csv (standard/premium/admin — mdp: password)"
echo ""

# =============================================================================
# SCÉNARIO 1 — Page simple (publique)
# =============================================================================
echo "📄 page_simple"
cat > "$FIXTURE_DIR/page_simple/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg,description,fe_group
1,0,"Test Page Simple","/test-page-simple",1,0,0,1,0,"Test meta description",0
CSV
echo -e "  ${GREEN}✓${NC} pages.csv"

# =============================================================================
# SCÉNARIO 2 — Page avec contenu texte (publique)
# =============================================================================
echo "📄 page_with_content"
cat > "$FIXTURE_DIR/page_with_content/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg,description,fe_group
2,0,"Test Page With Content","/test-page-with-content",1,0,0,1,0,"Test meta description with content",0
CSV
cat > "$FIXTURE_DIR/page_with_content/tt_content.csv" << 'CSV'
uid,pid,header,bodytext,CType,colPos,sorting,hidden,deleted,header_layout
10,2,"Test Introduction","Lorem ipsum dolor sit amet consectetur adipiscing elit","text",0,1,0,0,2
11,2,"Test Section Two","Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua","text",0,2,0,0,2
12,2,"Test Section Three","Ut enim ad minim veniam quis nostrud exercitation ullamco","text",0,3,0,0,2
CSV
echo -e "  ${GREEN}✓${NC} pages.csv + tt_content.csv (3 éléments)"

# =============================================================================
# SCÉNARIO 3 — Page avec images (publique)
# =============================================================================
echo "📄 page_with_images"
cat > "$FIXTURE_DIR/page_with_images/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg,fe_group
3,0,"Test Page With Images","/test-page-with-images",1,0,0,1,0,0
CSV
cat > "$FIXTURE_DIR/page_with_images/tt_content.csv" << 'CSV'
uid,pid,header,bodytext,CType,colPos,sorting,hidden,deleted,image
20,3,"Test Image Section","Lorem ipsum with image","textpic",0,1,0,0,1
CSV
cat > "$FIXTURE_DIR/page_with_images/sys_file.csv" << 'CSV'
uid,pid,identifier,name,extension,mime_type,size,missing,sha1
1,0,"/fileadmin/test-images/test-image-1.jpg","test-image-1.jpg","jpg","image/jpeg",12345,0,"abc123def456"
CSV
cat > "$FIXTURE_DIR/page_with_images/sys_file_reference.csv" << 'CSV'
uid,pid,uid_local,uid_foreign,tablenames,fieldname,sorting,hidden,deleted,title,description,alternative
1,0,1,20,"tt_content","image",1,0,0,"Test image title","Test image description","Test alt text"
CSV
echo -e "  ${GREEN}✓${NC} pages.csv + tt_content.csv + sys_file.csv + sys_file_reference.csv"

# =============================================================================
# SCÉNARIO 4 — Page avec catégories (publique)
# =============================================================================
echo "📄 page_with_categories"
cat > "$FIXTURE_DIR/page_with_categories/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg,fe_group
4,0,"Test Page With Categories","/test-page-with-categories",1,0,0,1,0,0
CSV
cat > "$FIXTURE_DIR/page_with_categories/tt_content.csv" << 'CSV'
uid,pid,header,bodytext,CType,colPos,sorting,hidden,deleted
30,4,"Test Categorized Content","Lorem ipsum categorized content","text",0,1,0,0
CSV
cat > "$FIXTURE_DIR/page_with_categories/sys_category.csv" << 'CSV'
uid,pid,title,description,hidden,deleted
1,0,"Test Category A","Description of test category A",0,0
2,0,"Test Category B","Description of test category B",0,0
CSV
cat > "$FIXTURE_DIR/page_with_categories/sys_category_record_mm.csv" << 'CSV'
uid_local,uid_foreign,tablenames,fieldname,sorting
30,1,"tt_content","categories",1
30,2,"tt_content","categories",2
CSV
echo -e "  ${GREEN}✓${NC} pages.csv + tt_content.csv + sys_category.csv + mm.csv"

# =============================================================================
# SCÉNARIO 5 — Page protégée (nécessite FE user connecté)
# fe_group=1 → accessible au groupe standard (uid=1)
# =============================================================================
echo "📄 page_protected"
cat > "$FIXTURE_DIR/page_protected/pages.csv" << 'CSV'
uid,pid,title,slug,doktype,hidden,deleted,is_siteroot,l18n_cfg,fe_group
5,0,"Test Protected Page","/test-protected-page",1,0,0,1,0,1
CSV
cat > "$FIXTURE_DIR/page_protected/tt_content.csv" << 'CSV'
uid,pid,header,bodytext,CType,colPos,sorting,hidden,deleted
40,5,"Test Protected Content","Contenu réservé aux membres connectés","text",0,1,0,0
41,5,"Test Premium Content","Contenu réservé aux membres premium","text",0,2,0,0
CSV
# Copier les fixtures partagées
cp "$FIXTURE_DIR/shared/fe_groups.csv" "$FIXTURE_DIR/page_protected/fe_groups.csv"
cp "$FIXTURE_DIR/shared/fe_users.csv"  "$FIXTURE_DIR/page_protected/fe_users.csv"
echo -e "  ${GREEN}✓${NC} pages.csv (fe_group=1) + tt_content.csv + fe_groups.csv + fe_users.csv"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ FIXTURES GÉNÉRÉES${NC}"
echo "=========================================="
echo -e "📁 Dossier : ${YELLOW}$FIXTURE_DIR${NC}"
echo ""
echo "Taille totale :"
du -sh "$FIXTURE_DIR" 2>/dev/null | sed 's/^/  /'
echo ""
echo "Ces fixtures sont VERSIONNÉES dans Git (anonymisées, ~50 Ko)."
echo "Prochaine étape :"
echo "  UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless"
echo "=========================================="
