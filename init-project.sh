#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# init-project.sh — Inicializa un nuevo proyecto a partir
# de la plantilla SAML2 + Angular + Bamboo.
#
# Uso:
#   ./init-project.sh MiNuevoProyecto
#
# Esto reemplaza todos los nombres de la plantilla (SECIHTI,
# Secihti, secihti) con las variantes del nombre dado.
# También renombra el archivo .csproj.
# ─────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
  echo "Uso: $0 <NombreProyecto>"
  echo ""
  echo "Ejemplo: $0 MiAppNueva"
  echo ""
  echo "El nombre se usa para:"
  echo "  - Namespace C#:    NombreProyecto  (PascalCase tal como lo escribas)"
  echo "  - package.json:    nombreproyecto  (lowercase)"
  echo "  - Docker/logs:     nombreproyecto  (lowercase)"
  echo "  - SAML issuer:     nombreproyecto.tec.mx"
  exit 1
fi

PROJECT_NAME="$1"
# PascalCase tal como lo pasó el usuario (para namespaces C#)
PASCAL_CASE="$PROJECT_NAME"
# lowercase para docker, package.json, URLs
LOWER_CASE=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')

echo "╔══════════════════════════════════════════════╗"
echo "║  Inicializando proyecto: $PASCAL_CASE"
echo "╠══════════════════════════════════════════════╣"
echo "║  Namespace C#:  $PASCAL_CASE"
echo "║  Lowercase:     $LOWER_CASE"
echo "╚══════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Archivos a procesar (excluyendo .git, node_modules, bin, obj, dist, y este script)
FILES_TO_PROCESS=$(find "$SCRIPT_DIR" \
  -type f \
  ! -path '*/.git/*' \
  ! -path '*/node_modules/*' \
  ! -path '*/bin/*' \
  ! -path '*/obj/*' \
  ! -path '*/dist/*' \
  ! -path '*/.angular/*' \
  ! -name 'init-project.sh' \
  ! -name 'package-lock.json' \
  ! -name '*.png' \
  ! -name '*.ico' \
  ! -name '*.ttf' \
  ! -name '*.svg' \
  ! -name '*.woff' \
  ! -name '*.woff2' \
  \( -name '*.cs' -o -name '*.csproj' -o -name '*.json' -o -name '*.ts' -o -name '*.html' -o -name '*.yml' -o -name '*.yaml' -o -name '*.md' -o -name '*.css' -o -name '*.scss' -o -name 'Dockerfile*' -o -name '.env*' \))

REPLACED=0

for file in $FILES_TO_PROCESS; do
  if grep -q -E 'SECIHTI|Secihti|secihti' "$file" 2>/dev/null; then
    # SECIHTI (uppercase namespace) → PASCAL_CASE (uppercase)
    sed -i '' "s/SECIHTI/${PASCAL_CASE}/g" "$file" 2>/dev/null || sed -i "s/SECIHTI/${PASCAL_CASE}/g" "$file"
    # Secihti (PascalCase) → PASCAL_CASE
    sed -i '' "s/Secihti/${PASCAL_CASE}/g" "$file" 2>/dev/null || sed -i "s/Secihti/${PASCAL_CASE}/g" "$file"
    # secihti (lowercase) → LOWER_CASE
    sed -i '' "s/secihti/${LOWER_CASE}/g" "$file" 2>/dev/null || sed -i "s/secihti/${LOWER_CASE}/g" "$file"
    REPLACED=$((REPLACED + 1))
    echo "  ✓ $file"
  fi
done

# Actualizar el title en index.html
if [ -f "$SCRIPT_DIR/ClientApp/src/index.html" ]; then
  sed -i '' "s/<title>TEMPLATE<\/title>/<title>${PASCAL_CASE}<\/title>/g" "$SCRIPT_DIR/ClientApp/src/index.html" 2>/dev/null || \
  sed -i "s/<title>TEMPLATE<\/title>/<title>${PASCAL_CASE}<\/title>/g" "$SCRIPT_DIR/ClientApp/src/index.html"
  echo "  ✓ ClientApp/src/index.html (title)"
fi

# Actualizar nombre del proyecto en angular.json
if [ -f "$SCRIPT_DIR/ClientApp/angular.json" ]; then
  sed -i '' "s/\"TEMPLATE\"/\"${LOWER_CASE}\"/g" "$SCRIPT_DIR/ClientApp/angular.json" 2>/dev/null || \
  sed -i "s/\"TEMPLATE\"/\"${LOWER_CASE}\"/g" "$SCRIPT_DIR/ClientApp/angular.json"
  # También reemplazar en buildTarget references como "TEMPLATE:build"
  sed -i '' "s/TEMPLATE:/${LOWER_CASE}:/g" "$SCRIPT_DIR/ClientApp/angular.json" 2>/dev/null || \
  sed -i "s/TEMPLATE:/${LOWER_CASE}:/g" "$SCRIPT_DIR/ClientApp/angular.json"
  echo "  ✓ ClientApp/angular.json (project name)"
fi

# Renombrar el archivo .csproj
OLD_CSPROJ="$SCRIPT_DIR/Secihti.csproj"
NEW_CSPROJ="$SCRIPT_DIR/${PASCAL_CASE}.csproj"
if [ -f "$OLD_CSPROJ" ] && [ "$OLD_CSPROJ" != "$NEW_CSPROJ" ]; then
  mv "$OLD_CSPROJ" "$NEW_CSPROJ"
  echo "  ✓ Secihti.csproj → ${PASCAL_CASE}.csproj"
fi

# Limpiar archivos de la plantilla
rm -f "$SCRIPT_DIR/templateSAML2.txt" 2>/dev/null || true
rm -f "$SCRIPT_DIR/scan_project.py" 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ Proyecto '$PASCAL_CASE' inicializado."
echo "  Archivos actualizados: $REPLACED"
echo ""
echo "  Próximos pasos:"
echo "  1. Actualiza appsettings.json con tus URLs SAML y Key Vault"
echo "  2. Actualiza los environments de Angular"
echo "  3. Actualiza los workflows de CI/CD"
echo "  4. cd ClientApp && npm install --legacy-peer-deps"
echo "  5. dotnet restore && dotnet run"
echo "═══════════════════════════════════════════════"
