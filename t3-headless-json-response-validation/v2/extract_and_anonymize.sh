#!/bin/bash
# =============================================================================
# extract_and_anonymize.sh
# Extrait des données depuis la base DDEV locale et les anonymise.
#
# ⚠️  SÉCURITÉ :
#   - Ne jamais exécuter contre la base de production
#   - Les fichiers générés sont gitignorés
#   - Toutes les données personnelles sont remplacées
#   - Les UIDs sont réassignés à des valeurs stables (1–10)
#
# Prérequis :
#   - DDEV démarré avec la base locale importée : ddev start
#   - La base locale peut contenir des données réelles — ce script les anonymise
#
# Usage :
#   ./Tests/Scripts/extract_and_anonymize.sh [page_uid_simple] [page_uid_content] ...
#   ./Tests/Scripts/extract_and_anonymize.sh 10 42 87 124
# =============================================================================

# UIDs des pages à extraire (passés en argument ou valeurs par défaut)
UID_SIMPLE=${1:-10}
UID_CONTENT=${2:-42}
UID_IMAGES=${3:-87}
UID_CATEGORIES=${4:-124}

FIXTURE_DIR="Tests/Fixtures/Database"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🔒 EXTRACTION + ANONYMISATION DEPUIS DDEV"
echo "=========================================="
echo -e "${YELLOW}⚠️  Les données personnelles seront anonymisées${NC}"
echo ""

# Vérifier que DDEV est disponible
if ! command -v ddev &> /dev/null; then
    echo -e "${RED}❌ DDEV introuvable. Installez DDEV ou utilisez generate_fixtures.sh.${NC}"
    exit 1
fi

# Vérifier que DDEV est démarré
if ! ddev status 2>/dev/null | grep -q "running"; then
    echo -e "${RED}❌ DDEV n'est pas démarré. Lancez : ddev start${NC}"
    exit 1
fi

mkdir -p \
  "$FIXTURE_DIR/page_simple" \
  "$FIXTURE_DIR/page_with_content" \
  "$FIXTURE_DIR/page_with_images" \
  "$FIXTURE_DIR/page_with_categories"

# =============================================================================
# Fonction d'extraction MySQL via DDEV
# =============================================================================
extract_table() {
    local table=$1
    local where=$2
    local output=$3

    ddev mysql -e "
        SELECT * FROM $table WHERE $where LIMIT 20
    " --batch 2>/dev/null | \
    awk 'NR==1 { gsub(/\t/, ","); print } NR>1 { gsub(/\t/, ","); print }' \
    > "$output"

    if [ -s "$output" ]; then
        echo -e "  ${GREEN}✓${NC} $table extrait ($(wc -l < "$output") lignes)"
    else
        echo -e "  ${YELLOW}⚠${NC}  $table vide — vérifiez l'UID"
        rm -f "$output"
    fi
}

# =============================================================================
# Fonction d'anonymisation PHP via DDEV
# Remplace toutes les données sensibles dans un fichier CSV
# =============================================================================
anonymize_csv() {
    local file=$1
    local table=$2

    ddev php -r "
        \$file = '$file';
        \$table = '$table';
        if (!file_exists(\$file)) exit(0);

        \$lines = file(\$file, FILE_IGNORE_NEW_LINES);
        \$headers = str_getcsv(array_shift(\$lines));
        \$result = [implode(',', \$headers)];
        \$counter = 1;

        foreach (\$lines as \$line) {
            if (empty(trim(\$line))) continue;
            \$row = str_getcsv(\$line);
            \$data = array_combine(\$headers, \$row);

            // Champs dynamiques — supprimés
            foreach (['crdate', 'tstamp', 'lastUpdated', 'starttime', 'endtime'] as \$f) {
                if (isset(\$data[\$f])) \$data[\$f] = '0';
            }

            // Anonymisation selon la table
            if (\$table === 'pages') {
                if (isset(\$data['title'])) \$data['title'] = 'Test Page ' . \$counter;
                if (isset(\$data['description'])) \$data['description'] = 'Test meta description ' . \$counter;
                if (isset(\$data['slug'])) \$data['slug'] = '/test-page-' . \$counter;
                if (isset(\$data['og_title'])) \$data['og_title'] = 'Test OG Title ' . \$counter;
                if (isset(\$data['og_description'])) \$data['og_description'] = 'Test OG Description ' . \$counter;
                if (isset(\$data['twitter_title'])) \$data['twitter_title'] = '';
            }

            if (\$table === 'tt_content') {
                if (isset(\$data['header'])) \$data['header'] = 'Test Header ' . \$counter;
                if (isset(\$data['bodytext'])) \$data['bodytext'] = 'Lorem ipsum dolor sit amet consectetur adipiscing elit ' . \$counter;
                if (isset(\$data['subheader'])) \$data['subheader'] = 'Test Subheader ' . \$counter;
            }

            // Emails et téléphones — dans tous les champs
            foreach (\$data as \$k => \$v) {
                // Email pattern
                \$v = preg_replace('/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/', 'test-' . \$counter . '@example.com', \$v);
                // Téléphone pattern (FR)
                \$v = preg_replace('/(\+33|0)[0-9 .-]{8,14}/', '+33 0 00 00 00 0' . (\$counter % 10), \$v);
                // Nettoyage guillemets dans CSV
                \$data[\$k] = str_replace('"', '\"', \$v);
            }

            \$result[] = implode(',', array_map(fn(\$v) => strpos(\$v, ',') !== false ? '\"' . \$v . '\"' : \$v, \$data));
            \$counter++;
        }

        file_put_contents(\$file, implode(PHP_EOL, \$result) . PHP_EOL);
        echo 'Anonymisé : ' . basename(\$file) . PHP_EOL;
    " 2>/dev/null

    if [ $? -ne 0 ]; then
        echo -e "  ${RED}✗${NC} Échec anonymisation $file (DDEV PHP non disponible — utilisez generate_fixtures.sh)"
    fi
}

# =============================================================================
# Réassignation des UIDs
# Remplace les UIDs de production par des UIDs stables (1, 2, 3...)
# =============================================================================
reassign_uids() {
    local scenario=$1
    local target_page_uid=$2
    local new_page_uid=$3

    # Remplace tous les UIDs de la page cible par le nouvel UID dans tous les CSV
    for csv_file in "$FIXTURE_DIR/$scenario"/*.csv; do
        [ -f "$csv_file" ] || continue
        sed -i "s/\b$target_page_uid\b/$new_page_uid/g" "$csv_file"
    done
    echo -e "  ${GREEN}✓${NC} UIDs réassignés ($target_page_uid → $new_page_uid)"
}

# =============================================================================
# SCÉNARIO 1 — Page simple
# =============================================================================
echo "📄 Scénario 1 : page_simple (UID $UID_SIMPLE)"
extract_table "pages" "uid = $UID_SIMPLE" "$FIXTURE_DIR/page_simple/pages.csv"
anonymize_csv "$FIXTURE_DIR/page_simple/pages.csv" "pages"
reassign_uids "page_simple" "$UID_SIMPLE" "1"

# =============================================================================
# SCÉNARIO 2 — Page avec contenu
# =============================================================================
echo ""
echo "📄 Scénario 2 : page_with_content (UID $UID_CONTENT)"
extract_table "pages" "uid = $UID_CONTENT" "$FIXTURE_DIR/page_with_content/pages.csv"
extract_table "tt_content" "pid = $UID_CONTENT AND hidden = 0 AND deleted = 0" "$FIXTURE_DIR/page_with_content/tt_content.csv"
anonymize_csv "$FIXTURE_DIR/page_with_content/pages.csv" "pages"
anonymize_csv "$FIXTURE_DIR/page_with_content/tt_content.csv" "tt_content"
reassign_uids "page_with_content" "$UID_CONTENT" "2"

# =============================================================================
# SCÉNARIO 3 — Page avec images
# =============================================================================
echo ""
echo "📄 Scénario 3 : page_with_images (UID $UID_IMAGES)"
extract_table "pages" "uid = $UID_IMAGES" "$FIXTURE_DIR/page_with_images/pages.csv"
extract_table "tt_content" "pid = $UID_IMAGES AND hidden = 0 AND deleted = 0" "$FIXTURE_DIR/page_with_images/tt_content.csv"

# Extraction sys_file_reference liée aux tt_content de cette page
CONTENT_UIDS=$(ddev mysql -e "SELECT GROUP_CONCAT(uid) FROM tt_content WHERE pid = $UID_IMAGES AND hidden = 0" --batch --skip-column-names 2>/dev/null | tr -d '\n')
if [ -n "$CONTENT_UIDS" ]; then
    extract_table "sys_file_reference" "uid_foreign IN ($CONTENT_UIDS) AND tablenames = 'tt_content'" "$FIXTURE_DIR/page_with_images/sys_file_reference.csv"

    FILE_UIDS=$(ddev mysql -e "SELECT GROUP_CONCAT(uid_local) FROM sys_file_reference WHERE uid_foreign IN ($CONTENT_UIDS) AND tablenames = 'tt_content'" --batch --skip-column-names 2>/dev/null | tr -d '\n')
    if [ -n "$FILE_UIDS" ]; then
        extract_table "sys_file" "uid IN ($FILE_UIDS)" "$FIXTURE_DIR/page_with_images/sys_file.csv"
    fi
fi

anonymize_csv "$FIXTURE_DIR/page_with_images/pages.csv" "pages"
anonymize_csv "$FIXTURE_DIR/page_with_images/tt_content.csv" "tt_content"
reassign_uids "page_with_images" "$UID_IMAGES" "3"

# =============================================================================
# SCÉNARIO 4 — Page avec catégories
# =============================================================================
echo ""
echo "📄 Scénario 4 : page_with_categories (UID $UID_CATEGORIES)"
extract_table "pages" "uid = $UID_CATEGORIES" "$FIXTURE_DIR/page_with_categories/pages.csv"
extract_table "tt_content" "pid = $UID_CATEGORIES AND hidden = 0 AND deleted = 0" "$FIXTURE_DIR/page_with_categories/tt_content.csv"

CAT_CONTENT_UIDS=$(ddev mysql -e "SELECT GROUP_CONCAT(uid) FROM tt_content WHERE pid = $UID_CATEGORIES AND hidden = 0" --batch --skip-column-names 2>/dev/null | tr -d '\n')
if [ -n "$CAT_CONTENT_UIDS" ]; then
    extract_table "sys_category_record_mm" "uid_foreign IN ($CAT_CONTENT_UIDS)" "$FIXTURE_DIR/page_with_categories/sys_category_record_mm.csv"

    CAT_UIDS=$(ddev mysql -e "SELECT GROUP_CONCAT(uid_local) FROM sys_category_record_mm WHERE uid_foreign IN ($CAT_CONTENT_UIDS)" --batch --skip-column-names 2>/dev/null | tr -d '\n')
    if [ -n "$CAT_UIDS" ]; then
        extract_table "sys_category" "uid IN ($CAT_UIDS)" "$FIXTURE_DIR/page_with_categories/sys_category.csv"
    fi
fi

anonymize_csv "$FIXTURE_DIR/page_with_categories/pages.csv" "pages"
anonymize_csv "$FIXTURE_DIR/page_with_categories/tt_content.csv" "tt_content"
anonymize_csv "$FIXTURE_DIR/page_with_categories/sys_category.csv" "sys_category"
reassign_uids "page_with_categories" "$UID_CATEGORIES" "4"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ EXTRACTION + ANONYMISATION TERMINÉE${NC}"
echo "=========================================="
echo -e "📁 Fixtures dans : ${YELLOW}$FIXTURE_DIR${NC}"
echo ""
echo -e "${YELLOW}⚠️  Ces fichiers sont gitignorés — ne jamais les commiter.${NC}"
echo "Lancez UPDATE_SNAPSHOTS=1 vendor/bin/phpunit pour générer les snapshots."
echo "=========================================="
