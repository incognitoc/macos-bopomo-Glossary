#!/bin/bash
# 雙擊安裝：建置 → 複製到 ~/Applications → 建立安裝前備份 → 註冊右鍵服務。
set -euo pipefail
cd "$(dirname "$0")"

TARGET="$HOME/Applications/ㄅㄆㄇ字詞庫.app"

echo "=== 安裝ㄅㄆㄇ字詞庫 ==="
./build.sh

osascript -e 'tell application "ㄅㄆㄇ字詞庫" to quit' >/dev/null 2>&1 || true

# 舊版名稱「注音字詞」：移除舊 App，避免右鍵選單出現兩個服務。
LEGACY="$HOME/Applications/注音字詞.app"
if [ -d "$LEGACY" ]; then
  osascript -e 'tell application "注音字詞" to quit' >/dev/null 2>&1 || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$LEGACY" || true
  rm -rf "$LEGACY"
  echo "✓ 已移除舊版「注音字詞」"
fi

mkdir -p "$HOME/Applications"
rm -rf "$TARGET"
cp -R "build/ㄅㄆㄇ字詞庫.app" "$TARGET"
echo "✓ 已複製到 $TARGET"

"$TARGET/Contents/MacOS/ZhuyinDict" --install
open "$TARGET"
echo
echo "完成。在任何 App 反白文字 → 右鍵 → 服務 → 加入ㄅㄆㄇ字詞庫。"
