#!/bin/zsh
# Markdown Okuyucu'yu derler ve ~/Applications içine kurar.
set -e
cd "$(dirname "$0")"
APP="build/Markdown Okuyucu.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -module-name MarkdownOkuyucu main.swift \
  -framework Cocoa -framework WebKit -o "$APP/Contents/MacOS/MarkdownOkuyucu"
cp Info.plist "$APP/Contents/"
cp Resources/* "$APP/Contents/Resources/"
# Uygulama simgesi: docs/icon.png'den AppIcon.icns üret
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s docs/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  (( s <= 256 )) && sips -z $((s*2)) $((s*2)) docs/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --deep -s - "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/"Markdown Okuyucu.app"
cp -R "$APP" ~/Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"Markdown Okuyucu.app"
# Spotlight'ta ikinci kopya görünmesin diye derleme klasörünü sil
rm -rf build
echo "Kuruldu: ~/Applications/Markdown Okuyucu.app"
