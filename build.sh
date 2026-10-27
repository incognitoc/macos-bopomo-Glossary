#!/bin/bash
# 建置 build/注音字詞.app（只需要 Xcode Command Line Tools）。
set -euo pipefail
cd "$(dirname "$0")"

APP="build/注音字詞.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp

echo "→ 編譯"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/ZhuyinDict" Sources/*.swift -lsqlite3

echo "→ 產生圖示"
swiftc -O -o build/tmp/make_icon tools/make_icon.swift
rm -rf build/tmp/AppIcon.iconset
build/tmp/make_icon build/tmp/AppIcon.iconset
iconutil -c icns build/tmp/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "✓ 完成：$APP"
