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
xattr -cr "$APP"
codesign --force --deep -s - "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/"Markdown Okuyucu.app"
cp -R "$APP" ~/Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"Markdown Okuyucu.app"
echo "Kuruldu: ~/Applications/Markdown Okuyucu.app"
