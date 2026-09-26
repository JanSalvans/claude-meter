#!/bin/bash
# Compila Claude Meter en mode release i el munta com a app de macOS, sense Xcode.
# Ús: Scripts/bundle.sh [--open]
#   --open   obre l'app un cop instal·lada a ~/Applications.
set -euo pipefail

# --- Configuració ---------------------------------------------------------

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="ClaudeMeter"
APP_NAME="Claude Meter"
BUNDLE_ID="com.jansalvans.claudemeter"
VERSION="1.1.0"
BUILD_NUMBER="2"
INSTALL_DIR="$HOME/Applications"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

OPEN_AFTER=0
for arg in "$@"; do
  case "$arg" in
    --open)
      OPEN_AFTER=1
      ;;
    *)
      echo "Argument desconegut: $arg" >&2
      exit 1
      ;;
  esac
done

cd "$PROJECT_ROOT"

echo "==> Compilant en mode release..."
swift build -c release
echo "    Compilació feta."

BIN_PATH=".build/release/$EXECUTABLE_NAME"
if [ ! -f "$BIN_PATH" ]; then
  echo "ERROR: no trobo el binari a $BIN_PATH." >&2
  exit 1
fi

# --- Munta el bundle a un directori temporal abans d'instal·lar-lo --------

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

STAGING_APP="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$STAGING_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Muntant l'estructura del bundle..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"

INFO_PLIST_TEMPLATE="$PROJECT_ROOT/Resources/Info.plist"
if [ ! -f "$INFO_PLIST_TEMPLATE" ]; then
  echo "ERROR: no trobo la plantilla $INFO_PLIST_TEMPLATE." >&2
  exit 1
fi

sed \
  -e "s/__EXECUTABLE_NAME__/$EXECUTABLE_NAME/g" \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__BUILD__/$BUILD_NUMBER/g" \
  "$INFO_PLIST_TEMPLATE" > "$CONTENTS_DIR/Info.plist"

echo "    CFBundleIdentifier: $BUNDLE_ID"
echo "    Versió: $VERSION ($BUILD_NUMBER)"

# --- Signatura ad hoc -------------------------------------------------------
# Cal signar, encara que sigui ad hoc, perquè el Keychain i les notificacions
# funcionin de manera estable entre execucions.

echo "==> Signant amb identitat ad hoc..."
codesign --force --sign - --timestamp=none "$STAGING_APP"
echo "    Signat."

# --- Instal·la a ~/Applications, de manera idempotent ----------------------

mkdir -p "$INSTALL_DIR"

if [ -e "$APP_BUNDLE" ]; then
  BACKUP_DIR="$INSTALL_DIR/.claudemeter-backups"
  mkdir -p "$BACKUP_DIR"
  BACKUP_PATH="$BACKUP_DIR/$APP_NAME-$(date +%Y%m%d%H%M%S).app"
  echo "==> Ja hi ha una versió instal·lada, la desa com a còpia de seguretat..."
  mv "$APP_BUNDLE" "$BACKUP_PATH"
  echo "    Còpia desada a: $BACKUP_PATH"
fi

echo "==> Instal·lant a $APP_BUNDLE..."
cp -R "$STAGING_APP" "$APP_BUNDLE"
echo "    Instal·lat."

if [ "$OPEN_AFTER" -eq 1 ]; then
  echo "==> Obrint l'app..."
  open "$APP_BUNDLE"
fi

echo "==> Fet. Claude Meter és a $APP_BUNDLE."
