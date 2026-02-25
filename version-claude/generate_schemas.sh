#!/bin/bash
# ============================================================
# NOUVEAU FICHIER À CRÉER :
# Tests/Scripts/generate_schemas.sh
# ============================================================
# Génère les schemas JSON partiels réutilisables par tous les scénarios.
# Chaque schema couvre une zone de la réponse TYPO3 headless.
# Le schema principal de chaque scénario référence ces partiels via $ref.
# ============================================================

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
          "urlLocale": {
            "type": "string",
            "description": "Code langue de l'alternate"
          },
          "href": {
            "type": "string",
            "description": "URL de la version dans cette langue"
          }
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
      "title": {
        "type": "string",
        "minLength": 1,
        "description": "Libellé de l'entrée dans le fil d'Ariane"
      },
      "link": {
        "type": "string",
        "description": "URL de la page"
      },
      "current": {
        "type": "boolean",
        "description": "true uniquement pour la page courante (dernier élément)"
      },
      "active": {
        "type": "boolean",
        "description": "true si la page est dans le chemin actif"
      }
    },
    "additionalProperties": true
  }
}
EOF
echo "✓ partials/breadcrumbs.schema.json"

# ------------------------------------------------------------------
# partials/appearance.schema.json — Zone layout/backend layout
# ------------------------------------------------------------------
cat > "$SCHEMA_DIR/appearance.schema.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["layout", "backendLayout"],
  "properties": {
    "layout": {
      "type": "string",
      "description": "Layout frontend (valeur du champ layout de la page TYPO3)"
    },
    "backendLayout": {
      "type": "string",
      "description": "Backend layout sélectionné dans les propriétés de la page"
    },
    "spaceBefore": {
      "type": "string",
      "description": "Espace avant la page (champ tx_headless_space_before_class)"
    },
    "spaceAfter": {
      "type": "string",
      "description": "Espace après la page (champ tx_headless_space_after_class)"
    }
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
      "description": "Colonne principale (colPos=0)",
      "items": { "$ref": "#/definitions/contentElement" }
    },
    "colPos1": {
      "type": "array",
      "description": "Colonne secondaire (colPos=1)",
      "items": { "$ref": "#/definitions/contentElement" }
    },
    "colPos2": {
      "type": "array",
      "description": "Colonne tertiaire (colPos=2)",
      "items": { "$ref": "#/definitions/contentElement" }
    }
  },
  "definitions": {
    "contentElement": {
      "type": "object",
      "required": ["id", "type", "content"],
      "properties": {
        "id": {
          "type": "integer",
          "minimum": 1,
          "description": "UID du tt_content"
        },
        "type": {
          "type": "string",
          "description": "CType TYPO3 (text, textpic, image, bullets, etc.)"
        },
        "colPos": {
          "type": "integer",
          "description": "Numéro de colonne"
        },
        "appearance": {
          "type": "object",
          "description": "Apparence spécifique à l'élément de contenu"
        },
        "content": {
          "type": "object",
          "required": ["header"],
          "properties": {
            "header": {
              "type": "string",
              "description": "Titre de l'élément de contenu"
            },
            "headerLayout": {
              "type": "integer",
              "description": "Niveau de titre (0=défaut, 1=h1, 2=h2...)"
            },
            "bodytext": {
              "type": "string",
              "description": "Contenu texte (RTE)"
            }
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
# Schema principal mis à jour — référence tous les partiels via $ref
# ------------------------------------------------------------------
MAIN_SCHEMA_EXAMPLE="Tests/Fixtures/Schemas/page_with_content.schema.json"
cat > "$MAIN_SCHEMA_EXAMPLE" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["id", "type", "title", "slug", "meta", "i18n", "breadcrumbs", "appearance", "content"],
  "properties": {
    "id": {
      "type": "integer",
      "minimum": 1,
      "description": "UID de la page TYPO3"
    },
    "type": {
      "type": "string",
      "enum": ["pages"],
      "description": "Type de ressource retournée"
    },
    "title": {
      "type": "string",
      "minLength": 1,
      "description": "Titre de la page"
    },
    "slug": {
      "type": "string",
      "pattern": "^/",
      "description": "Slug de la page (commence par /)"
    },
    "meta": {
      "$ref": "partials/meta.schema.json",
      "description": "Zone SEO (title, robots, canonical, og:*)"
    },
    "i18n": {
      "$ref": "partials/i18n.schema.json",
      "description": "Zone internationalisation (langue, locale, hreflang, alternates)"
    },
    "breadcrumbs": {
      "$ref": "partials/breadcrumbs.schema.json",
      "description": "Zone fil d'Ariane"
    },
    "appearance": {
      "$ref": "partials/appearance.schema.json",
      "description": "Zone layout et backend layout"
    },
    "content": {
      "$ref": "partials/content.schema.json",
      "description": "Zone contenu par colonne (colPos0, colPos1...)"
    }
  }
}
EOF
echo "✓ page_with_content.schema.json (exemple — dupliquer pour les autres scénarios)"

echo ""
echo "=========================================="
echo "✅ SCHEMAS GÉNÉRÉS"
echo "=========================================="
echo "📁 Schemas partiels : $SCHEMA_DIR"
echo ""
echo "👉 Dupliquer page_with_content.schema.json pour les autres scénarios :"
echo "   cp Tests/Fixtures/Schemas/page_with_content.schema.json Tests/Fixtures/Schemas/page_simple.schema.json"
echo "   cp Tests/Fixtures/Schemas/page_with_content.schema.json Tests/Fixtures/Schemas/page_with_images.schema.json"
echo "   cp Tests/Fixtures/Schemas/page_with_content.schema.json Tests/Fixtures/Schemas/page_with_categories.schema.json"
echo "=========================================="
