#!/bin/bash
# =============================================================================
# setup-git-hooks.sh
# Configure les hooks Git pour le projet TYPO3 Headless.
# À exécuter une seule fois après git clone.
#
# Hooks installés :
#   pre-commit       → bloque les snapshots JSON (jamais dans Git)
#   post-merge       → alerte si le dump ou les schemas changent
#   prepare-commit-msg → rappel BREAKING CHANGE si schema modifié
# =============================================================================

HOOKS_DIR=".git/hooks"
mkdir -p "$HOOKS_DIR"

GREEN='\033[0;32m'
NC='\033[0m'

echo "=========================================="
echo "🔧 CONFIGURATION DES HOOKS GIT"
echo "=========================================="

# =============================================================================
# pre-commit : bloque uniquement les snapshots
# Le dump SQL dans tests/database/ EST autorisé (c'est une donnée partagée)
# =============================================================================
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
BLOCKED=0

# Bloquer les snapshots JSON (gitignorés — générés localement)
if git diff --cached --name-only | grep -q "Tests/Fixtures/Snapshots/"; then
    echo ""
    echo "❌ COMMIT BLOQUÉ : snapshots JSON détectés."
    echo "   Tests/Fixtures/Snapshots/ est gitignored."
    echo "   Retirez-les : git reset HEAD Tests/Fixtures/Snapshots/"
    echo ""
    BLOCKED=1
fi

# Avertissement si le dump est modifié sans message explicite
if git diff --cached --name-only | grep -q "tests/database/"; then
    echo ""
    echo "ℹ️  Dump de base modifié : tests/database/"
    echo "   Assurez-vous d'avoir :"
    echo "   1. Lancé le cleanup sur l'EC2 : ./Tests/Scripts/cleanup_ec2.sh"
    echo "   2. Exporté le dump : ./Tests/Scripts/export_dump.sh"
    echo "   3. Un message de commit explicite : chore(db): update dump after [feature/cleanup]"
    echo ""
    # Pas bloquant — juste un rappel
fi

exit $BLOCKED
HOOK
chmod +x "$HOOKS_DIR/pre-commit"
echo -e "${GREEN}✓${NC} pre-commit (bloque snapshots, avertit sur dump)"

# =============================================================================
# post-merge : alerte selon ce qui a changé
# =============================================================================
cat > "$HOOKS_DIR/post-merge" << 'HOOK'
#!/bin/bash
CHANGED_DUMP=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "tests/database/")
CHANGED_SCHEMAS=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Fixtures/Schemas/")
CHANGED_SCRIPTS=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Scripts/")

if [ -n "$CHANGED_DUMP" ]; then
    echo ""
    echo "📥 DUMP DE RÉFÉRENCE MIS À JOUR :"
    echo "$CHANGED_DUMP" | sed 's/^/   /'
    echo ""
    echo "   Importez la nouvelle base :"
    echo "   ./Tests/Scripts/import_dump.sh"
    echo ""
    echo "   Régénérez vos snapshots locaux :"
    echo "   UPDATE_SNAPSHOTS=1 vendor/bin/phpunit \\"
    echo "     -c typo3/sysext/core/Build/FunctionalTests.xml \\"
    echo "     Tests/Functional/Headless"
    echo ""
fi

if [ -n "$CHANGED_SCHEMAS" ]; then
    echo ""
    echo "⚠️  SCHEMAS JSON modifiés :"
    echo "$CHANGED_SCHEMAS" | sed 's/^/   /'
    echo ""
    echo "   Backend  → UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
    echo "   Frontend → npx json-schema-to-typescript Tests/Fixtures/Schemas/partials/*.schema.json -o front/src/types/api/"
    echo ""
fi

if [ -n "$CHANGED_SCRIPTS" ]; then
    echo ""
    echo "ℹ️  Scripts modifiés :"
    echo "$CHANGED_SCRIPTS" | sed 's/^/   /'
    echo ""
fi
HOOK
chmod +x "$HOOKS_DIR/post-merge"
echo -e "${GREEN}✓${NC} post-merge (alerte dump + schemas + scripts)"

# =============================================================================
# prepare-commit-msg : rappel BREAKING CHANGE si schema modifié
# =============================================================================
cat > "$HOOKS_DIR/prepare-commit-msg" << 'HOOK'
#!/bin/bash
COMMIT_MSG_FILE=$1
SCHEMA_CHANGES=$(git diff --cached --name-only | grep "Tests/Fixtures/Schemas/")
DUMP_CHANGES=$(git diff --cached --name-only | grep "tests/database/")

if [ -n "$SCHEMA_CHANGES" ] && ! grep -q "BREAKING CHANGE" "$COMMIT_MSG_FILE"; then
    printf "\n# Schemas JSON modifiés — si breaking, ajoutez :\n# BREAKING CHANGE: description\n# Champs affectés, composants frontend concernés\n" \
        >> "$COMMIT_MSG_FILE"
fi

if [ -n "$DUMP_CHANGES" ]; then
    printf "\n# Dump de base mis à jour — indiquez la raison :\n# chore(db): update dump after [feature/monthly-cleanup]\n" \
        >> "$COMMIT_MSG_FILE"
fi
HOOK
chmod +x "$HOOKS_DIR/prepare-commit-msg"
echo -e "${GREEN}✓${NC} prepare-commit-msg (rappel BREAKING CHANGE + dump)"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ HOOKS CONFIGURÉS${NC}"
echo "=========================================="
echo ""
echo "Prochaine étape (si vous venez de cloner le dépôt) :"
echo "  ./Tests/Scripts/import_dump.sh"
echo "=========================================="
