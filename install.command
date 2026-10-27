#!/bin/bash
# 雙擊安裝：建置 → 複製到 ~/Applications → 建立安裝前備份 → 註冊右鍵服務。
set -euo pipefail
cd "$(dirname "$0")"

TARGET="$HOME/Applications/注音字詞.app"

echo "=== 安裝注音字詞 ==="
./build.sh

osascript -e 'tell application "注音字詞" to quit' >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$TARGET"
cp -R "build/注音字詞.app" "$TARGET"
echo "✓ 已複製到 $TARGET"

"$TARGET/Contents/MacOS/ZhuyinDict" --install
open "$TARGET"
echo
echo "完成。在任何 App 反白文字 → 右鍵 → 服務 → 加入注音字詞。"
