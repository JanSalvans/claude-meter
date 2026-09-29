#!/bin/bash
# Empaqueta Claude Meter per publicar-lo: app universal (Apple Silicon i Intel),
# signada ad hoc i comprimida en un zip a dist/. No instal·la res.
# Ús: Scripts/package.sh
set -euo pipefail

# --- Configuració ---------------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="ClaudeMeter"
APP_NAME="Claude Meter"
VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"
BUILD_NUMBER="$(grep -E '^BUILD_NUMBER=' "$PROJECT_ROOT/Scripts/bundle.sh" | cut -d'"' -f2)"
MIN_MACOS="13.0"
DIST_DIR="$PROJECT_ROOT/dist"
ZIP_PATH="$DIST_DIR/Claude-Meter-$VERSION.zip"

cd "$PROJECT_ROOT"

# --- Compila per a les dues arquitectures i les uneix ----------------------

for ARCH in arm64 x86_64; do
  echo "==> Compilant per a $ARCH..."
  swift build -c release --triple "$ARCH-apple-macosx$MIN_MACOS"
done

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

STAGING_APP="$STAGING_DIR/$APP_NAME.app"
MACOS_DIR="$STAGING_APP/Contents/MacOS"
mkdir -p "$MACOS_DIR" "$STAGING_APP/Contents/Resources"

echo "==> Unint els binaris en un de sol (universal)..."
lipo -create \
  ".build/arm64-apple-macosx/release/$EXECUTABLE_NAME" \
  ".build/x86_64-apple-macosx/release/$EXECUTABLE_NAME" \
  -output "$MACOS_DIR/$EXECUTABLE_NAME"
lipo -info "$MACOS_DIR/$EXECUTABLE_NAME"

sed \
  -e "s/__EXECUTABLE_NAME__/$EXECUTABLE_NAME/g" \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__BUILD__/$BUILD_NUMBER/g" \
  "$PROJECT_ROOT/Resources/Info.plist" > "$STAGING_APP/Contents/Info.plist"

# --- Signatura ad hoc i zip -------------------------------------------------
# Sense Apple Developer Program no es pot notaritzar: el primer cop macOS
# demanarà confirmació per obrir-la (vegeu el README).

echo "==> Signant amb identitat ad hoc..."
codesign --force --sign - --timestamp=none "$STAGING_APP"
codesign --verify --strict "$STAGING_APP"

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
echo "==> Comprimint..."
ditto -c -k --sequesterRsrc --keepParent "$STAGING_APP" "$ZIP_PATH"

echo "==> Fet: $ZIP_PATH ($VERSION, build $BUILD_NUMBER)"
