#!/bin/zsh
# Compile Island et produit build/Island.app (100 % local, aucun compte développeur requis).
#
# Usage : scripts/build-app.sh [--run] [--install]
#   --run      lance l'app après compilation (en fermant l'instance existante)
#   --install  copie l'app dans ~/Applications
#
# Signature : certificat auto-signé « Island Local Signing » s'il est dans le trousseau
# (macOS garde alors les permissions d'un build à l'autre), sinon ad-hoc.
# CODESIGN_IDENTITY permet d'en forcer un autre.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Island.app"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  IDENTITY="$CODESIGN_IDENTITY"
elif security find-certificate -c "Island Local Signing" >/dev/null 2>&1; then
  IDENTITY="Island Local Signing"
else
  IDENTITY="-"
fi

cd "$ROOT"
swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/Island" "$APP/Contents/MacOS/Island"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Adaptateur MediaRemote (lecture en cours) : framework chargé par /usr/bin/perl, pas lié à l'app.
ADAPTER="$ROOT/Vendor/mediaremote-adapter"
FRAMEWORK="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
mkdir -p "$FRAMEWORK/Versions/A/Resources"
clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -mmacosx-version-min=15.0 -O2 \
  -I"$ADAPTER/include" -I"$ADAPTER/src" \
  "$ADAPTER"/src/adapter/*.m "$ADAPTER"/src/private/*.m "$ADAPTER"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$FRAMEWORK/Versions/A/MediaRemoteAdapter"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.elion.island.MediaRemoteAdapter</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
PLIST
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FRAMEWORK/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
codesign --force --sign "$IDENTITY" "$FRAMEWORK"

codesign --force --sign "$IDENTITY" "$APP"
echo "✓ $APP (signature : $IDENTITY)"

for arg in "$@"; do
  case "$arg" in
    --install)
      mkdir -p "$HOME/Applications"
      rm -rf "$HOME/Applications/Island.app"
      cp -R "$APP" "$HOME/Applications/"
      APP="$HOME/Applications/Island.app"
      echo "✓ installée dans $APP"
      ;;
  esac
done

for arg in "$@"; do
  if [[ "$arg" == "--run" ]]; then
    pkill -x Island 2>/dev/null || true
    sleep 0.3
    open "$APP"
  fi
done
