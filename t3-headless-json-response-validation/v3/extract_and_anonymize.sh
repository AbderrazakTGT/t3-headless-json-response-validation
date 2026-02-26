#!/bin/bash
# =============================================================================
# extract_and_anonymize.sh
# Extrait des données représentatives depuis la base DDEV et les anonymise.
#
# ✅ Filtre deleted=0 automatiquement sur toutes les tables
# ✅ Limite à 30 enregistrements par table (vs 1,3 Go)
# ✅ Anonymise emails, téléphones, noms, slugs
# ✅ Génère 3 fe_users de test avec rôles (standard/premium/admin)
# ✅ Réassigne les UIDs de production → UIDs stables 1–10
# ✅ Résultat : ~30–50 Ko par scénario, versionnables dans Git
#
# Prérequis :
#   - DDEV démarré : ddev start
#   - Recommandé : ./Tests/Scripts/cleanup_database.sh --min-age=30 avant
#
# Usage :
#   ./Tests/Scripts/extract_and_anonymize.sh [uid_simple] [uid_content] [uid_images] [uid_categories] [uid_protected]
#   ./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124 200
# =============================================================================

UID_SIMPLE=${1:-10}
UID_CONTENT=${2:-42}
UID_IMAGES=${3:-87}
UID_CATEGORIES=${4:-124}
UID_PROTECTED=${5:-200}

FIXTURE_DIR="Tests/Fixtures/Database"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "🔒 EXTRACTION + ANONYMISATION DEPUIS DDEV"
echo "=========================================="
echo -e "${YELLOW}⚠️  Données personnelles anonymisées${NC}"
echo -e "${BLUE}ℹ️  deleted=0 forcé sur toutes les requêtes${NC}"
echo -e "${BLUE}ℹ️  Taille cible : 30–50 Ko par scénario${NC}"
echo ""

if ! command -v ddev &> /dev/null; then
    echo -e "${RED}❌ DDEV introuvable — utilisez generate_fixtures.sh${NC}"
    exit 1
fi
if ! ddev status 2>/dev/null | grep -q "running"; then
    echo -e "${RED}❌ DDEV non démarré. Lancez : ddev start${NC}"
    exit 1
fi

# Avertissement si cleanup_database.sh n'a pas été lancé
REMAINING=$(ddev mysql -e "SELECT COUNT(*) FROM pages WHERE deleted=1" \
    --batch --skip-column-names 2>/dev/null | tr -d '\n')
if [ "${REMAINING:-0}" -gt 100 ]; then
    echo -e "${YELLOW}⚠️  ${REMAINING} pages avec deleted=1 détectées.${NC}"
    echo "   Lancez ./Tests/Scripts/cleanup_database.sh avant extraction."
    echo ""
fi

mkdir -p \
  "$FIXTURE_DIR/shared" \
  "$FIXTURE_DIR/page_simple" \
  "$FIXTURE_DIR/page_with_content" \
  "$FIXTURE_DIR/page_with_images" \
  "$FIXTURE_DIR/page_with_categories" \
  "$FIXTURE_DIR/page_protected"

# =============================================================================
# extract_table : extraction MySQL avec filtre deleted=0 automatique
# =============================================================================
extract_table() {
    local table=$1
    local where=$2
    local output=$3
    local limit=${4:-30}

    # Ajouter deleted=0 si la table a ce champ et qu'il n'est pas déjà dans le WHERE
    HAS_DELETED=$(ddev mysql -e "SHOW COLUMNS FROM \`$table\` LIKE 'deleted'" \
        --batch --skip-column-names 2>/dev/null)
    if [ -n "$HAS_DELETED" ] && [[ "$where" != *"deleted"* ]]; then
        where="($where) AND deleted=0"
    fi

    ddev mysql -e "SELECT * FROM \`$table\` WHERE $where LIMIT $limit" \
        --batch 2>/dev/null | \
        awk 'NR==1{gsub(/\t/,",");print} NR>1{gsub(/\t/,",");print}' \
        > "$output"

    if [ -s "$output" ]; then
        local lines=$(wc -l < "$output")
        echo -e "  ${GREEN}✓${NC} $table — $((lines-1)) lignes (deleted=0 filtrés)"
    else
        echo -e "  ${YELLOW}⚠${NC}  $table vide ou UID invalide"
        rm -f "$output"
    fi
}

# =============================================================================
# anonymize_csv : anonymisation PHP de toutes les données sensibles
# =============================================================================
anonymize_csv() {
    local file=$1
    local table=$2

    [ -f "$file" ] || return

    ddev php << PHPEOF
<?php
\$file  = '$file';
\$table = '$table';
\$lines = file(\$file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if (count(\$lines) < 2) exit(0);

\$headers = str_getcsv(array_shift(\$lines));
\$result  = [implode(',', \$headers)];
\$n       = 1;

foreach (\$lines as \$line) {
    \$row = str_getcsv(\$line);
    if (count(\$row) !== count(\$headers)) continue;
    \$d = array_combine(\$headers, \$row);

    // Champs dynamiques → 0
    foreach (['crdate','tstamp','lastUpdated','starttime','endtime','lastlogin'] as \$f) {
        if (array_key_exists(\$f, \$d)) \$d[\$f] = '0';
    }

    // Anonymisation par table
    switch (\$table) {
        case 'pages':
            \$d['title']          = "Test Page \$n";
            \$d['slug']           = "/test-page-\$n";
            if (isset(\$d['description']))    \$d['description']    = "Test meta description \$n";
            if (isset(\$d['og_title']))       \$d['og_title']       = "Test OG Title \$n";
            if (isset(\$d['og_description'])) \$d['og_description'] = "Test OG Description \$n";
            if (isset(\$d['author']))         \$d['author']         = "Test Author \$n";
            if (isset(\$d['author_email']))   \$d['author_email']   = "author-\$n@example.com";
            break;
        case 'tt_content':
            if (isset(\$d['header']))    \$d['header']    = "Test Header \$n";
            if (isset(\$d['subheader'])) \$d['subheader'] = "Test Subheader \$n";
            if (isset(\$d['bodytext']))  \$d['bodytext']  = "Lorem ipsum dolor sit amet \$n";
            break;
        case 'sys_category':
            if (isset(\$d['title']))       \$d['title']       = "Test Category \$n";
            if (isset(\$d['description'])) \$d['description'] = "Test category description \$n";
            break;
        case 'fe_groups':
            if (isset(\$d['title']))       \$d['title']       = "test_group_\$n";
            if (isset(\$d['description'])) \$d['description'] = "Test group \$n";
            break;
    }

    // Patterns sensibles dans tous les champs
    foreach (\$d as \$k => \$v) {
        \$v = preg_replace('/[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/',
                           "test-\$n@example.com", \$v);
        \$v = preg_replace('/(\+33|0)[0-9 .\-]{8,14}/',
                           "+33 0 00 00 00 0" . (\$n % 10), \$v);
        \$d[\$k] = str_replace('"', '""', \$v);
    }

    \$result[] = implode(',', array_map(
        fn(\$v) => preg_match('/[,"\n]/', \$v) ? '"'.\$v.'"' : \$v,
        \$d
    ));
    \$n++;
}

file_put_contents(\$file, implode(PHP_EOL, \$result) . PHP_EOL);
echo "Anonymisé : " . basename(\$file) . " (" . (\$n-1) . " lignes)" . PHP_EOL;
PHPEOF
}

# =============================================================================
# reassign_uids : remplace les UIDs production → UIDs stables 1–10
# =============================================================================
reassign_uids() {
    local scenario=$1
    local old_uid=$2
    local new_uid=$3
    for csv in "$FIXTURE_DIR/$scenario"/*.csv; do
        [ -f "$csv" ] || continue
        sed -i "s/\b$old_uid\b/$new_uid/g" "$csv"
    done
    echo -e "  ${GREEN}✓${NC} UID $old_uid → $new_uid"
}

# =============================================================================
# SHARED — FE groups extraits + FE users synthétiques
# Les fe_users ne sont JAMAIS extraits de la prod — créés de zéro
# =============================================================================
echo -e "${BLUE}👥 FE groups (extraction) + FE users (synthétiques)${NC}"

# Extraire les groupes existants (max 3, sans données sensibles)
extract_table "fe_groups" "hidden=0" "$FIXTURE_DIR/shared/fe_groups.csv" 3
anonymize_csv "$FIXTURE_DIR/shared/fe_groups.csv" "fe_groups"

# Récupérer les UIDs de groupes disponibles
G1=$(ddev mysql -e "SELECT uid FROM fe_groups WHERE hidden=0 AND deleted=0 LIMIT 1 OFFSET 0" \
    --batch --skip-column-names 2>/dev/null | tr -d '\n')
G2=$(ddev mysql -e "SELECT uid FROM fe_groups WHERE hidden=0 AND deleted=0 LIMIT 1 OFFSET 1" \
    --batch --skip-column-names 2>/dev/null | tr -d '\n')
G1=${G1:-1}; G2=${G2:-2}

# FE users synthétiques (jamais extraits de la prod)
HASH='$2y$12$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'
cat > "$FIXTURE_DIR/shared/fe_users.csv" << CSV
uid,pid,username,password,usergroup,name,first_name,last_name,email,telephone,address,zip,city,country,hidden,deleted,disable,crdate,tstamp,lastlogin
100,0,"test_standard","$HASH","$G1","Test Standard User","Test","Standard","test-standard@example.com","","","","","",0,0,0,0,0,0
101,0,"test_premium","$HASH","$G1,$G2","Test Premium User","Test","Premium","test-premium@example.com","","","","","",0,0,0,0,0,0
102,0,"test_admin","$HASH","$G1,$G2","Test Admin User","Test","Admin","test-admin@example.com","","","","","",0,0,0,0,0,0
CSV
echo -e "  ${GREEN}✓${NC} fe_users.csv — 3 comptes (mdp: password)"
echo ""

# =============================================================================
# SCÉNARIO 1 — Page simple
# =============================================================================
echo "📄 page_simple (UID $UID_SIMPLE)"
extract_table "pages" "uid=$UID_SIMPLE" "$FIXTURE_DIR/page_simple/pages.csv"
anonymize_csv "$FIXTURE_DIR/page_simple/pages.csv" "pages"
reassign_uids "page_simple" "$UID_SIMPLE" "1"

# =============================================================================
# SCÉNARIO 2 — Page avec contenu
# =============================================================================
echo ""
echo "📄 page_with_content (UID $UID_CONTENT)"
extract_table "pages" "uid=$UID_CONTENT" "$FIXTURE_DIR/page_with_content/pages.csv"
extract_table "tt_content" "pid=$UID_CONTENT AND hidden=0" \
    "$FIXTURE_DIR/page_with_content/tt_content.csv" 30
anonymize_csv "$FIXTURE_DIR/page_with_content/pages.csv" "pages"
anonymize_csv "$FIXTURE_DIR/page_with_content/tt_content.csv" "tt_content"
reassign_uids "page_with_content" "$UID_CONTENT" "2"

# =============================================================================
# SCÉNARIO 3 — Page avec images
# =============================================================================
echo ""
echo "📄 page_with_images (UID $UID_IMAGES)"
extract_table "pages" "uid=$UID_IMAGES" "$FIXTURE_DIR/page_with_images/pages.csv"
extract_table "tt_content" "pid=$UID_IMAGES AND hidden=0" \
    "$FIXTURE_DIR/page_with_images/tt_content.csv" 30

CT_UIDS=$(ddev mysql -e \
    "SELECT GROUP_CONCAT(uid) FROM tt_content WHERE pid=$UID_IMAGES AND hidden=0 AND deleted=0" \
    --batch --skip-column-names 2>/dev/null | tr -d '\n')

if [ -n "$CT_UIDS" ] && [ "$CT_UIDS" != "NULL" ]; then
    extract_table "sys_file_reference" \
        "uid_foreign IN ($CT_UIDS) AND tablenames='tt_content'" \
        "$FIXTURE_DIR/page_with_images/sys_file_reference.csv"
    F_UIDS=$(ddev mysql -e \
        "SELECT GROUP_CONCAT(uid_local) FROM sys_file_reference WHERE uid_foreign IN ($CT_UIDS) AND tablenames='tt_content' AND deleted=0" \
        --batch --skip-column-names 2>/dev/null | tr -d '\n')
    if [ -n "$F_UIDS" ] && [ "$F_UIDS" != "NULL" ]; then
        extract_table "sys_file" "uid IN ($F_UIDS)" "$FIXTURE_DIR/page_with_images/sys_file.csv"
    fi
fi
anonymize_csv "$FIXTURE_DIR/page_with_images/pages.csv" "pages"
anonymize_csv "$FIXTURE_DIR/page_with_images/tt_content.csv" "tt_content"
reassign_uids "page_with_images" "$UID_IMAGES" "3"

# =============================================================================
# SCÉNARIO 4 — Page avec catégories
# =============================================================================
echo ""
echo "📄 page_with_categories (UID $UID_CATEGORIES)"
extract_table "pages" "uid=$UID_CATEGORIES" "$FIXTURE_DIR/page_with_categories/pages.csv"
extract_table "tt_content" "pid=$UID_CATEGORIES AND hidden=0" \
    "$FIXTURE_DIR/page_with_categories/tt_content.csv" 30

CAT_CT_UIDS=$(ddev mysql -e \
    "SELECT GROUP_CONCAT(uid) FROM tt_content WHERE pid=$UID_CATEGORIES AND hidden=0 AND deleted=0" \
    --batch --skip-column-names 2>/dev/null | tr -d '\n')

if [ -n "$CAT_CT_UIDS" ] && [ "$CAT_CT_UIDS" != "NULL" ]; then
    extract_table "sys_category_record_mm" \
        "uid_foreign IN ($CAT_CT_UIDS)" \
        "$FIXTURE_DIR/page_with_categories/sys_category_record_mm.csv"
    CAT_UIDS=$(ddev mysql -e \
        "SELECT GROUP_CONCAT(uid_local) FROM sys_category_record_mm WHERE uid_foreign IN ($CAT_CT_UIDS)" \
        --batch --skip-column-names 2>/dev/null | tr -d '\n')
    if [ -n "$CAT_UIDS" ] && [ "$CAT_UIDS" != "NULL" ]; then
        extract_table "sys_category" "uid IN ($CAT_UIDS)" \
            "$FIXTURE_DIR/page_with_categories/sys_category.csv"
        anonymize_csv "$FIXTURE_DIR/page_with_categories/sys_category.csv" "sys_category"
    fi
fi
anonymize_csv "$FIXTURE_DIR/page_with_categories/pages.csv" "pages"
anonymize_csv "$FIXTURE_DIR/page_with_categories/tt_content.csv" "tt_content"
reassign_uids "page_with_categories" "$UID_CATEGORIES" "4"

# =============================================================================
# SCÉNARIO 5 — Page protégée (FE user requis)
# =============================================================================
echo ""
echo "📄 page_protected (UID $UID_PROTECTED)"
extract_table "pages" "uid=$UID_PROTECTED" "$FIXTURE_DIR/page_protected/pages.csv"
extract_table "tt_content" "pid=$UID_PROTECTED AND hidden=0" \
    "$FIXTURE_DIR/page_protected/tt_content.csv" 10
anonymize_csv "$FIXTURE_DIR/page_protected/pages.csv" "pages"
anonymize_csv "$FIXTURE_DIR/page_protected/tt_content.csv" "tt_content"
reassign_uids "page_protected" "$UID_PROTECTED" "5"
cp "$FIXTURE_DIR/shared/fe_groups.csv" "$FIXTURE_DIR/page_protected/fe_groups.csv"
cp "$FIXTURE_DIR/shared/fe_users.csv"  "$FIXTURE_DIR/page_protected/fe_users.csv"
echo -e "  ${GREEN}✓${NC} fe_groups.csv + fe_users.csv copiés depuis shared/"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ EXTRACTION + ANONYMISATION TERMINÉE${NC}"
echo "=========================================="
echo -e "📁 Fixtures dans : ${YELLOW}$FIXTURE_DIR${NC}"
echo ""
echo "Taille extraite :"
du -sh "$FIXTURE_DIR"/* 2>/dev/null | sed 's/^/  /'
echo ""
echo "Ces fixtures sont VERSIONNÉES dans Git (anonymisées)."
echo "Vérifiez le contenu avant git add :"
echo "  grep -r '@' $FIXTURE_DIR --include='*.csv' | grep -v '@example.com'"
echo ""
echo "Ensuite :"
echo "  git add Tests/Fixtures/Database/"
echo "  UPDATE_SNAPSHOTS=1 vendor/bin/phpunit -c typo3/sysext/core/Build/FunctionalTests.xml Tests/Functional/Headless"
echo "=========================================="
