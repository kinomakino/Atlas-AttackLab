#!/usr/bin/env bash
# Prepara una versión publicable del instalador en la web pública:
#   site/install.sh, site/install.ps1, site/install.sha256 y site/lab/<versión>/compose*.yaml
# Uso: deploy/release.sh <versión> <url base de la web>
set -euo pipefail
VERSION="${1:?versión, p. ej. 0.1.0}"
BASE_URL="${2:?url base, p. ej. https://atlas.seguridadsi.com}"
OUT="${3:-site}"
cd "$(dirname "$0")/.."

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

mkdir -p "$OUT/lab/$VERSION"
cp deploy/compose.yaml deploy/compose.gpu.yaml "$OUT/lab/$VERSION/"
C=$(sha deploy/compose.yaml); G=$(sha deploy/compose.gpu.yaml)

for f in install.sh install.ps1; do
  sed -e "s|__VERSION__|$VERSION|g" -e "s|__BASE_URL__|$BASE_URL|g" \
      -e "s|__COMPOSE_SHA256__|$C|g" -e "s|__COMPOSE_GPU_SHA256__|$G|g" "deploy/$f" > "$OUT/$f"
done
chmod +x "$OUT/install.sh"
( cd "$OUT" && for f in install.sh install.ps1; do echo "$(sha "$f")  $f"; done ) > "$OUT/install.sha256"
echo "Versión $VERSION preparada en $OUT/:"
cat "$OUT/install.sha256"
