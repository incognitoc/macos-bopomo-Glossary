#!/bin/bash
# 打包 build/ㄅㄆㄇ字詞庫-<版本>.dmg：裡面只放 App，雙擊打開就會自動安裝到 ~/Applications。
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

NAME="ㄅㄆㄇ字詞庫"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="build/$NAME-$VERSION.dmg"
STAGE="build/dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/$NAME.app" "$STAGE/"

echo "→ 打包 DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "✓ 完成：$DMG"
