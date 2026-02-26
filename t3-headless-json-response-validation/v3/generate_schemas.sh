#!/bin/bash
# =============================================================================
# generate_schemas.sh
# Génère les schemas JSON partiels réutilisables (versionnés dans Git).
# Aucune donnée — uniquement la structure et les types attendus.
# =============================================================================

SCHEMA_DIR="Tests/Fixtures/Schemas/partials"
mkdir -p "$SCHEMA_DIR"

echo "=========================================="
echo "📐 GÉNÉRATION DES SCHEMAS PARTIELS"
echo "=========================================="

# ------------------------------------------------------------------
# partials/meta.schema.json — Zone SEO
# ------------------------------------------------------------------
cat > "$SCHEMA_DIR/meta.schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["title", "robots"],
  "properties": {
    "title": {
      "type": "string",
      "minLength": 1,
      "description": "Titre de la page pour le <title> HTML"
    },
    "description": {
      "type": "string",
      "description": "Meta description SEO"
    },
    "ogTitle": {
      "type": "string",
      "description": "Titre Open Graph"
    },
    "ogDescription": {
      "type": "string",
      "description": "Description Open Graph"
    },
    "ogImage": {
      "type": "string",
      "pattern": "^/fileadmin/",
      "description": "Image Open Graph, doit pointer vers /fileadmin/"
    },
    "robots": {
      "type": "string",
      "pattern": "^(index|noindex),(follow|nofollow)$",
      "description": "Directive robots : index/noindex,follow/nofollow"
    },
    "canonical": {
      "type": "string",
      "pattern": "^https?://",
      "description": "URL canonique absolue"
    },
    "twitterCard": {
      "type": "string",
      "enum": ["summary", "summary_large_image", "app", "player"]
    }
  },
  "additionalProperties": true
}
EOF
echo "✓ partials/meta.schema.json"

# ------------------------------------------------------------------
# partials/i18n.schema.json — Zone internationalisation
# ------------------------------------------------------------------
cat > "$SCHEMA_DIR/i18n.schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["language", "locale", "hreflang", "alternates"],
  "properties": {
    "language": {
      "type": "integer",
      "minimum": 0,
      "description": "ID de la langue TYPO3 (0 = langue par défaut)"
    },
    "locale": {
      "type": "string",
      "pattern": "^[a-z]{2}_[A-Z]{2}\\.UTF-8$",
      "description": "Locale système ex: fr_FR.UTF-8"
    },
    "hreflang": {
      "type": "string",
      "pattern": "^[a-z]{2}(-[a-z]{2})?$",
      "description": "Code hreflang ex: fr-fr, en-gb"
    },
    "direction": {
      "type": "string",
      "enum": ["", "ltr", "rtl"],
      "description": "Direction du texte"
    },
    "flag": {
      "type": "string",
      "description": "Code du drapeau de la langue"
    },
    "navigationTitle": {
      "type": "string",
      "description": "Titre utilisé dans la navigation"
    },
    "alternates": {
      "type": "array",
      "description": "Liens hreflang vers les autres versions linguistiques",
      "items": {
        "type": "object",
        "required": ["urlLocale", "href"],
        "properties": {
          "urlLocale": { "type": "string" },
          "href": { "type": "string" }
        }
      }
    }
  },
  "additionalProperties": true
}
EOF
echo "✓ partials/i18n.schema.json"

# ------------------------------------------------------------------
# partials/breadcrumbs.schema.json — Zone fil d'Ariane
# ------------------------------------------------------------------
cat > "$SCHEMA_DIR/breadcrumbs.schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "minItems": 1,
  "description": "Fil d'Ariane — le premier élément est toujours la racine (/)",
  "items": {
    "type": "object",
    "required": ["title", "link"],
    "properties": {
      "title": { "type": "string", "minLength": 1 },
      "link": { "type": "string" },
      "current": { "type": "boolean" },
      "active": { "type": "boolean" }
    },
    "additionalProperties": true
  }
}
EOF
echo "✓ partials/breadcrumbs.schema.json"

# ------------------------------------------------------------------
# partials/appearance.schema.json — Zone layout
# ------------------------------------------------------------------
cat > "$SCHEMA_DIR/appearance.schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["layout", "backendLayout"],
  "properties": {
    "layout": {
      "type": "string",
      "description": "Layout frontend"
    },
    "backendLayout": {
      "type": "string",
      "description": "Backend layout TYPO3"
    },
    "spaceBefore": { "type": "string" },
    "spaceAfter": { "type": "string" }
  },
  "additionalProperties": true
}
EOF
echo "✓ partials/appearance.schema.json"

# ------------------------------------------------------------------
# partials/content.schema.json — Zone contenu (colPos)
# ------------------------------------------------------------------
cat > "$SCHEMA_DIR/content.schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "description": "Contenu de la page organisé par colonne (colPos)",
  "required": ["colPos0"],
  "properties": {
    "colPos0": {
      "type": "array",
      "description": "Colonne principale",
      "items": { "$ref": "#/definitions/contentElement" }
    },
    "colPos1": {
      "type": "array",
      "items": { "$ref": "#/definitions/contentElement" }
    },
    "colPos2": {
      "type": "array",
      "items": { "$ref": "#/definitions/contentElement" }
    }
  },
  "definitions": {
    "contentElement": {
      "type": "object",
      "required": ["id", "type", "content"],
      "properties": {
        "id": { "type": "integer", "minimum": 1 },
        "type": { "type": "string" },
        "colPos": { "type": "integer" },
        "appearance": { "type": "object" },
        "content": {
          "type": "object",
          "required": ["header"],
          "properties": {
            "header": { "type": "string" },
            "headerLayout": { "type": "integer" },
            "bodytext": { "type": "string" }
          },
          "additionalProperties": true
        }
      },
      "additionalProperties": true
    }
  },
  "additionalProperties": true
}
EOF
echo "✓ partials/content.schema.json"

# ------------------------------------------------------------------
# Schemas principaux — un par scénario, référençant les partiels
# ------------------------------------------------------------------
for scenario in page_simple page_with_content page_with_images page_with_categories; do
cat > "Tests/Fixtures/Schemas/${scenario}.schema.json" << EOF
{
  "\$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["id", "type", "title", "slug", "meta", "i18n", "breadcrumbs", "appearance", "content"],
  "properties": {
    "id":    { "type": "integer", "minimum": 1 },
    "type":  { "type": "string", "enum": ["pages"] },
    "title": { "type": "string", "minLength": 1 },
    "slug":  { "type": "string", "pattern": "^/" },
    "meta":        { "\$ref": "partials/meta.schema.json" },
    "i18n":        { "\$ref": "partials/i18n.schema.json" },
    "breadcrumbs": { "\$ref": "partials/breadcrumbs.schema.json" },
    "appearance":  { "\$ref": "partials/appearance.schema.json" },
    "content":     { "\$ref": "partials/content.schema.json" }
  }
}
EOF
  echo "✓ ${scenario}.schema.json"
done

echo ""
echo "=========================================="
echo "✅ SCHEMAS GÉNÉRÉS (versionnés dans Git)"
echo "=========================================="
echo "📁 Partiels : $SCHEMA_DIR"
echo "📁 Principaux : Tests/Fixtures/Schemas/"
echo "=========================================="
