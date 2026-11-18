#!/usr/bin/env bash
set -euo pipefail
app=build/Build/Products/Release-iphoneos/OpenWhisper.app
ext="$app/PlugIns/Clavier.appex"
id() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist"; }
[[ "$(id "$ext" NSExtension:NSExtensionPointIdentifier)" == com.apple.keyboard-service ]]
[[ "$(id "$ext" CFBundleIdentifier)" == "$(id "$app" CFBundleIdentifier)".clavier ]]
for bundle in "$app" "$ext" "$app/Frameworks/whisper.framework"; do
  binary="$bundle/$(id "$bundle" CFBundleExecutable)"
  xcrun lipo -verify_arch arm64 "$binary"
  xcrun vtool -show-build "$binary" | grep -Eq 'platform IOS$'
done
for bundle in "$app" "$ext"; do
  if codesign --verify "$bundle" 2>/dev/null; then echo "Signature inattendue : $bundle" >&2; exit 1; fi
done
mkdir -p dist
staging=$(mktemp -d "$PWD/dist/staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir "$staging/Payload"
ditto "$app" "$staging/Payload/OpenWhisper.app"
(cd "$staging" && /usr/bin/zip -qry OpenWhisper-unsigned.ipa Payload)
python3 scripts/verify-ipa.py "$staging/OpenWhisper-unsigned.ipa"
mv "$staging/OpenWhisper-unsigned.ipa" dist/OpenWhisper-unsigned.ipa
(cd dist && shasum -a 256 OpenWhisper-unsigned.ipa > SHA256.txt)
