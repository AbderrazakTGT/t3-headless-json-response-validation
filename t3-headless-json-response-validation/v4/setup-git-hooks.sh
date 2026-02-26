#!/bin/bash
# =============================================================================
# setup-git-hooks.sh
# Configure les hooks Git pour protéger le principe "aucune donnée dans Git".
# À exécuter une seule fois après git clone.
#
# PRINCIPE : AUCUNE DONNÉE DANS GIT
#   ❌ Tests/Fixtures/Database/  → gitignored (CSV fixtures)
#   ❌ Tests/Fixtures/Snapshots/ → gitignored (JSON snapshots)
#
# Hooks installés :
#   pre-commit       → bloque tout commit de données (CSV ou snapshots)
#   post-merge       → alerte si les schemas ou scripts changent
#   prepare-commit-msg → rappel BREAKING CHANGE si schema modifié
# =============================================================================

HOOKS_DIR=".git/hooks"
mkdir -p "$HOOKS_DIR"

GREEN='\033[0;32m'
NC='\033[0m'

echo "=========================================="
echo "🔧 CONFIGURATION DES HOOKS GIT"
echo "=========================================="
echo "Principe : AUCUNE DONNÉE DANS GIT"
echo ""

# =============================================================================
# pre-commit : bloque Database/ ET Snapshots/
# =============================================================================
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
BLOCKED=0

# Bloquer les fixtures CSV (gitignorés)
if git diff --cached --name-only | grep -q "Tests/Fixtures/Database/"; then
    echo ""
    echo "❌ COMMIT BLOQUÉ : fixtures CSV détectées (Tests/Fixtures/Database/)."
    echo "   Ces fichiers sont gitignorés — AUCUNE DONNÉE DANS GIT."
    echo "   Retirez-les : git reset HEAD Tests/Fixtures/Database/"
    echo ""
    BLOCKED=1
fi

# Bloquer les snapshots JSON (gitignorés)
if git diff --cached --name-only | grep -q "Tests/Fixtures/Snapshots/"; then
    echo ""
    echo "❌ COMMIT BLOQUÉ : snapshots JSON détectés (Tests/Fixtures/Snapshots/)."
    echo "   Ces fichiers sont gitignorés — AUCUNE DONNÉE DANS GIT."
    echo "   Retirez-les : git reset HEAD Tests/Fixtures/Snapshots/"
    echo ""
    BLOCKED=1
fi

# Scan de sécurité : détecter des emails réels dans les fichiers stagés
# (filet de sécurité si quelqu'un force --no-verify sur .gitignore)
for file in $(git diff --cached --name-only --diff-filter=ACM | grep -E "\.(csv|json)$"); do
    EMAILS=$(git show ":$file" 2>/dev/null \
        | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
        | grep -v "@example\.com" | head -3)
    if [ -n "$EMAILS" ]; then
        echo "⚠️  Email potentiellement réel dans $file :"
        echo "   $EMAILS"
        echo "   Vérifiez — AUCUNE DONNÉE SENSIBLE DANS GIT."
        BLOCKED=1
    fi
done

exit $BLOCKED
HOOK
chmod +x "$HOOKS_DIR/pre-commit"
echo -e "${GREEN}✓${NC} pre-commit (bloque Database/ + Snapshots/ + emails)"

# =============================================================================
# post-merge : alerte sur changements de schemas et scripts
# =============================================================================
cat > "$HOOKS_DIR/post-merge" << 'HOOK'
#!/bin/bash
CHANGED_SCHEMAS=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Fixtures/Schemas/")
CHANGED_SCRIPTS=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Scripts/")

if [ -n "$CHANGED_SCHEMAS" ]; then
    echo ""
    echo "⚠️  SCHEMAS JSON modifiés :"
    echo "$CHANGED_SCHEMAS" | sed 's/^/   /'
    echo ""
    echo "   Actions requises :"
    echo "   Backend  → ./Tests/Scripts/generate_fixtures.sh"
    echo "              UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
    echo "   Frontend → npx json-schema-to-typescript Tests/Fixtures/Schemas/partials/*.schema.json -o front/src/types/api/"
    echo ""
fi

if [ -n "$CHANGED_SCRIPTS" ]; then
    echo ""
    echo "ℹ️  Scripts de fixtures modifiés :"
    echo "$CHANGED_SCRIPTS" | sed 's/^/   /'
    echo "   Régénérez vos fixtures locales :"
    echo "   ./Tests/Scripts/generate_fixtures.sh"
    echo "   UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
    echo ""
fi
HOOK
chmod +x "$HOOKS_DIR/post-merge"
echo -e "${GREEN}✓${NC} post-merge (alerte schemas + scripts)"

# =============================================================================
# prepare-commit-msg : rappel BREAKING CHANGE si schema modifié
# =============================================================================
cat > "$HOOKS_DIR/prepare-commit-msg" << 'HOOK'
#!/bin/bash
COMMIT_MSG_FILE=$1
SCHEMA_CHANGES=$(git diff --cached --name-only | grep "Tests/Fixtures/Schemas/")

if [ -n "$SCHEMA_CHANGES" ] && ! grep -q "BREAKING CHANGE" "$COMMIT_MSG_FILE"; then
    printf "\n# Schemas JSON modifiés — si breaking, ajoutez :\n# BREAKING CHANGE: description du changement\n# Champs affectés, composants frontend concernés\n" \
        >> "$COMMIT_MSG_FILE"
fi
HOOK
chmod +x "$HOOKS_DIR/prepare-commit-msg"
echo -e "${GREEN}✓${NC} prepare-commit-msg (rappel BREAKING CHANGE)"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ HOOKS CONFIGURÉS${NC}"
echo "=========================================="
echo "Chaque développeur doit exécuter ce script après git clone."
echo ""
echo "Rappel : générer vos données locales :"
echo "  ./Tests/Scripts/generate_fixtures.sh"
echo "  UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
echo "=========================================="
