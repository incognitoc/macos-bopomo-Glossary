#!/bin/bash
# 雙擊卸載：處理字詞 → 移除 App 與右鍵服務。備份資料夾會保留。
set -euo pipefail

TARGET="$HOME/Applications/ㄅㄆㄇ字詞庫.app"
BIN="$TARGET/Contents/MacOS/ZhuyinDict"

echo "=== 卸載ㄅㄆㄇ字詞庫 ==="
if [ ! -x "$BIN" ]; then
  echo "找不到 $TARGET，可能已經卸載了。"
  exit 0
fi

echo "已加入的字詞要怎麼處理？"
echo "  1) 保留全部字詞（預設）"
echo "  2) 只刪除本程式加入的字詞"
echo "  3) 還原到安裝前的備份"
read -r -p "請輸入 1、2 或 3：" choice
case "${choice:-1}" in
  2) MODE=mine ;;
  3) MODE=restore ;;
  *) MODE=keep ;;
esac

osascript -e 'tell application "ㄅㄆㄇ字詞庫" to quit' >/dev/null 2>&1 || true
"$BIN" --uninstall "$MODE"

rm -rf "$TARGET" "$HOME/Applications/注音字詞.app"
/System/Library/CoreServices/pbs -update
echo "✓ 已移除 App 與右鍵服務"
echo "備份保留在：$HOME/Library/Application Support/ZhuyinDict/Backups"
