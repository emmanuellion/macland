#!/bin/zsh
# Compile macland puis produit build/macland-<version>.dmg (glisser l'app dans Applications).
#
# L'app n'est pas notarisée (pas de compte développeur Apple) : au premier lancement,
# macOS la bloque ; il faut l'autoriser dans Réglages Système › Confidentialité et sécurité.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="$ROOT/build/macland-$VERSION.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R build/macland.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "macland" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
