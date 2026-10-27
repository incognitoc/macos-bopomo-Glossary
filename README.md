# ㄅㄆㄇ字詞庫（macOS Bopomofo Glossary）

macOS 的注音輸入法常記不住常用的詞。這個 App 把常用詞寫進系統的「文字替代」，注音輸入法會把它們列成候選字，也會透過 iCloud 同步到其他裝置。

## 功能

- 新增、編輯、刪除字詞，依來源（自建／右鍵加入／系統原有）篩選
- 縮寫自動用聲母首字產生（快到了 → ㄎㄉㄌ），破音字可切換讀音；縮寫留白時存檔自動補上
- 在任何 App 反白文字 → 右鍵 → 服務 → + ㄅㄆㄇ字詞庫
- 匯入／匯出 plist 或 CSV
- 每次寫入前自動備份，卸載時可選保留、只刪本程式加入的、或還原到安裝前備份
- Liquid Glass 介面

## 安裝與卸載

需要 Xcode Command Line Tools。

- 安裝：雙擊 `install.command`（建置後安裝到 `~/Applications`）
- 卸載：雙擊 `uninstall.command`，或在 App 的「安裝與卸載…」裡操作

備份存放在 `~/Library/Application Support/ZhuyinDict/Backups`，卸載後仍會保留。

## 技術說明

- 讀取：唯讀 `~/Library/KeyboardServices/TextReplacements.db`
- 寫入：透過系統設定使用的私有框架 `KeyboardServices`（`_KSTextReplacementClientStore`），才會即時同步到輸入法與 iCloud。這不是公開 API，未來系統更新可能失效
- Mac 的文字替代不接受空白縮寫，也不接受跟詞一樣的縮寫
