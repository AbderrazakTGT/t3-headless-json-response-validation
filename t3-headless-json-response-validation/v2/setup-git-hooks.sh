#!/bin/bash
# =============================================================================
# setup-git-hooks.sh
# Configure les hooks Git pour les deux équipes.
# À exécuter une seule fois après git clone.
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOOKS_DIR=".git/hooks"
mkdir -p "$HOOKS_DIR"

echo "=========================================="
echo "🔧 CONFIGURATION DES HOOKS GIT"
echo "=========================================="

# =============================================================================
# pre-commit — vérifie qu'aucune donnée sensible n'est commitée
# =============================================================================
cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Vérifie qu'aucun fichier sensible n'est stagé

BLOCKED=0

# Fixtures CSV
if git diff --cached --name-only | grep -q "Tests/Fixtures/Database/"; then
    echo "❌ COMMIT BLOQUÉ : des fichiers CSV de fixtures sont stagés."
    echo "   Tests/Fixtures/Database/ est gitignored — retirez-les :"
    echo "   git reset HEAD Tests/Fixtures/Database/"
    BLOCKED=1
fi

# Snapshots JSON
if git diff --cached --name-only | grep -q "Tests/Fixtures/Snapshots/"; then
    echo "❌ COMMIT BLOQUÉ : des snapshots JSON sont stagés."
    echo "   Tests/Fixtures/Snapshots/ est gitignored — retirez-les :"
    echo "   git reset HEAD Tests/Fixtures/Snapshots/"
    BLOCKED=1
fi

# Emails réels dans les fichiers stagés (hors @example.com)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(php|json|csv|sh)$')
for file in $STAGED_FILES; do
    EMAILS=$(git show ":$file" 2>/dev/null | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | grep -v "@example\.com" | head -3)
    if [ -n "$EMAILS" ]; then
        echo "⚠️  Email potentiellement réel dans $file : $EMAILS"
        echo "   Vérifiez que ce fichier ne contient pas de données personnelles."
    fi
done

exit $BLOCKED
EOF
chmod +x "$HOOKS_DIR/pre-commit"
echo -e "${GREEN}✓${NC} pre-commit (bloque CSV/Snapshots + détecte emails)"

# =============================================================================
# post-merge — alerte le frontend si les schemas changent
# =============================================================================
cat > "$HOOKS_DIR/post-merge" << 'EOF'
#!/bin/bash
# Détecte les changements de schemas et alerte les équipes

CHANGED_SCHEMAS=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Fixtures/Schemas/")
CHANGED_SCRIPTS=$(git diff HEAD@{1} HEAD --name-only 2>/dev/null | grep "Tests/Scripts/")

if [ -n "$CHANGED_SCHEMAS" ]; then
    echo ""
    echo "⚠️  SCHEMAS JSON MODIFIÉS — actions requises :"
    echo "$CHANGED_SCHEMAS" | sed 's/^/   - /'
    echo ""
    echo "   Backend : régénérer les fixtures et snapshots locaux"
    echo "   ./Tests/Scripts/generate_fixtures.sh"
    echo "   UPDATE_SNAPSHOTS=1 vendor/bin/phpunit ..."
    echo ""
    echo "   Frontend : régénérer les types TypeScript"
    echo "   npx json-schema-to-typescript Tests/Fixtures/Schemas/partials/*.schema.json -o front/src/types/api/"
    echo ""
fi

if [ -n "$CHANGED_SCRIPTS" ]; then
    echo "ℹ️  Scripts de test modifiés — relancez generate_fixtures.sh si nécessaire"
fi
EOF
chmod +x "$HOOKS_DIR/post-merge"
echo -e "${GREEN}✓${NC} post-merge (alerte changements schemas)"

# =============================================================================
# prepare-commit-msg — rappel BREAKING CHANGE pour les schemas
# =============================================================================
cat > "$HOOKS_DIR/prepare-commit-msg" << 'EOF'
#!/bin/bash
COMMIT_MSG_FILE=$1
COMMIT_SOURCE=$2

# Si des schemas sont modifiés, rappeler la convention BREAKING CHANGE
if git diff --cached --name-only | grep -q "Tests/Fixtures/Schemas/"; then
    if ! grep -q "BREAKING CHANGE" "$COMMIT_MSG_FILE"; then
        echo "" >> "$COMMIT_MSG_FILE"
        echo "# ⚠️  Des schemas JSON sont modifiés dans ce commit." >> "$COMMIT_MSG_FILE"
        echo "# Si c'est un changement breaking, ajoutez :" >> "$COMMIT_MSG_FILE"
        echo "# BREAKING CHANGE: description du changement" >> "$COMMIT_MSG_FILE"
        echo "# Champs affectés, composants frontend concernés" >> "$COMMIT_MSG_FILE"
    fi
fi
EOF
chmod +x "$HOOKS_DIR/prepare-commit-msg"
echo -e "${GREEN}✓${NC} prepare-commit-msg (rappel BREAKING CHANGE)"

echo ""
echo "=========================================="
echo -e "${GREEN}✅ HOOKS CONFIGURÉS${NC}"
echo "=========================================="
echo "Ces hooks s'appliquent uniquement à votre dépôt local."
echo "Chaque développeur doit lancer ce script après git clone."
echo "=========================================="
