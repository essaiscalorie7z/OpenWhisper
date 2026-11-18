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
mkdir -p dist/Payload
ditto "$app" dist/Payload/OpenWhisper.app
(cd dist && /usr/bin/zip -qry OpenWhisper-unsigned.ipa Payload)
unzip -tq dist/OpenWhisper-unsigned.ipa
shasum -a 256 dist/OpenWhisper-unsigned.ipa > dist/SHA256.txt
