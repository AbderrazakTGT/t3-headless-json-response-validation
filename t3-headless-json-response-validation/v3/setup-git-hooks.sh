#!/bin/bash
# =============================================================================
# setup-git-hooks.sh
# Configure les hooks Git pour les équipes backend et frontend.
# À exécuter une seule fois après git clone.
#
# ✅ Fixtures CSV versionnées → commit autorisé (après vérif anonymisation)
# ❌ Snapshots JSON gitignorés → commit bloqué
# =============================================================================

HOOKS_DIR=".git/hooks"
mkdir -p "$HOOKS_DIR"

GREEN='\033[0;32m'
NC='\033[0m'

echo "=========================================="
echo "🔧 CONFIGURATION DES HOOKS GIT"
echo "=========================================="

# =============================================================================
# pre-commit : bloque snapshots, vérifie anonymisation des CSV
# =============================================================================
cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
BLOCKED=0

# Bloquer les snapshots JSON (gitignorés)
if git diff --cached --name-only | grep -q "Tests/Fixtures/Snapshots/"; then
    echo ""
    echo "❌ COMMIT BLOQUÉ : snapshots JSON stagés (gitignorés)."
    echo "   git reset HEAD Tests/Fixtures/Snapshots/"
    BLOCKED=1
fi

# Vérifier l'anonymisation dans les CSV de fixtures (versionnés)
for file in $(git diff --cached --name-only --diff-filter=ACM | grep "Tests/Fixtures/Database/.*\.csv$"); do
    EMAILS=$(git show ":$file" 2>/dev/null \
        | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
        | grep -v "@example\.com" | head -3)
    if [ -n "$EMAILS" ]; then
        echo "⚠️  Email potentiellement réel dans $file : $EMAILS"
        echo "   Vérifiez l'anonymisation."
    fi
done

exit $BLOCKED
EOF
chmod +x "$HOOKS_DIR/pre-commit"
echo -e "${GREEN}✓${NC} pre-commit (bloque snapshots, vérifie emails CSV)"

# =============================================================================
# post-merge : alerte sur changements de schemas et fixtures
# =============================================================================
cat > "$HOOKS_DIR/post-merge" << 'EOF'
#!/bin/bash
CHANGED_SCHEMAS=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Fixtures/Schemas/")
CHANGED_FIXTURES=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Fixtures/Database/")

if [ -n "$CHANGED_SCHEMAS" ]; then
    echo ""
    echo "⚠️  SCHEMAS JSON modifiés :"
    echo "$CHANGED_SCHEMAS" | sed 's/^/   /'
    echo ""
    echo "   Backend  → UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
    echo "   Frontend → npx json-schema-to-typescript Tests/Fixtures/Schemas/partials/*.schema.json -o front/src/types/api/"
fi

if [ -n "$CHANGED_FIXTURES" ]; then
    echo ""
    echo "ℹ️  Fixtures CSV mises à jour :"
    echo "$CHANGED_FIXTURES" | sed 's/^/   /'
    echo "   Régénérez vos snapshots : UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
fi
EOF
chmod +x "$HOOKS_DIR/post-merge"
echo -e "${GREEN}✓${NC} post-merge (alerte schemas + fixtures)"

# =============================================================================
# prepare-commit-msg : rappel BREAKING CHANGE si schema modifié
# =============================================================================
cat > "$HOOKS_DIR/prepare-commit-msg" << 'EOF'
#!/bin/bash
COMMIT_MSG_FILE=$1
SCHEMA_CHANGES=$(git diff --cached --name-only | grep "Tests/Fixtures/Schemas/")
FIXTURE_CHANGES=$(git diff --cached --name-only | grep "Tests/Fixtures/Database/")

if [ -n "$SCHEMA_CHANGES" ] && ! grep -q "BREAKING CHANGE" "$COMMIT_MSG_FILE"; then
    printf "\n# Schemas modifiés — si breaking, ajoutez :\n# BREAKING CHANGE: description\n# Champs affectés, composants frontend concernés\n" \
        >> "$COMMIT_MSG_FILE"
fi

if [ -n "$FIXTURE_CHANGES" ]; then
    printf "\n# Fixtures CSV modifiées — vérifiez l'anonymisation :\n# grep -r '@' Tests/Fixtures/Database --include='*.csv' | grep -v '@example.com'\n" \
        >> "$COMMIT_MSG_FILE"
fi
EOF
chmod +x "$HOOKS_DIR/prepare-commit-msg"
echo -e "${GREEN}✓${NC} prepare-commit-msg (rappel BREAKING CHANGE + anonymisation)"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ HOOKS CONFIGURÉS${NC}"
echo "=========================================="
echo "Chaque développeur doit lancer ce script après git clone."
echo "=========================================="
