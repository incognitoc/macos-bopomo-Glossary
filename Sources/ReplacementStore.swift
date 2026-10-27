import Foundation
import SQLite3

/// 系統「文字替代」裡的一筆資料。
struct Entry: Identifiable, Hashable {
    let id: String
    var phrase: String
    /// 系統實際儲存的縮寫；iPhone 上沒有縮寫的詞同步過來會存成跟詞本身一樣。
    var shortcut: String
    var date: Date

    var displayShortcut: String { shortcut == phrase ? "" : shortcut }
    var key: String { Entry.makeKey(shortcut: shortcut, phrase: phrase) }

    static func makeKey(shortcut: String, phrase: String) -> String {
        "\(shortcut)\u{1F}\(phrase)"
    }
}

enum StoreError: LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "無法連到系統的文字替代服務"
        case .failed(let message): return message
        }
    }
}

/// 讀取：直接唯讀 TextReplacements.db。
/// 寫入：透過系統設定使用的 KeyboardServices 服務，才會同步到輸入法與 iCloud。
final class ReplacementStore {
    static let dbURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/KeyboardServices/TextReplacements.db")

    private static let frameworkPath = "/System/Library/PrivateFrameworks/KeyboardServices.framework/KeyboardServices"

    private lazy var client: NSObject? = {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let cls = NSClassFromString("_KSTextReplacementClientStore") as? NSObject.Type
        else { return nil }
        return cls.init()
    }()

    func fetchAll() throws -> [Entry] {
        try Self.read(url: Self.dbURL)
    }

    static func read(url: URL) throws -> [Entry] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw StoreError.failed("讀不到文字替代資料庫")
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT ZUNIQUENAME, ZPHRASE, ZSHORTCUT, ZTIMESTAMP FROM ZTEXTREPLACEMENTENTRY
            WHERE ZWASDELETED = 0 OR ZWASDELETED IS NULL
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.failed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var entries: [Entry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ column: Int32) -> String {
                sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
            }
            let name = text(0)
            entries.append(Entry(
                id: name.isEmpty ? UUID().uuidString : name,
                phrase: text(1),
                shortcut: text(2),
                date: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 3))
            ))
        }
        return entries
    }

    static func backup(to url: URL) throws {
        var source: OpaquePointer?
        var target: OpaquePointer?
        defer {
            sqlite3_close(source)
            sqlite3_close(target)
        }
        guard sqlite3_open_v2(dbURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open(url.path, &target) == SQLITE_OK,
              let backup = sqlite3_backup_init(target, "main", source, "main")
        else { throw StoreError.failed("備份失敗") }
        sqlite3_backup_step(backup, -1)
        guard sqlite3_backup_finish(backup) == SQLITE_OK else { throw StoreError.failed("備份失敗") }
    }

    /// 新增與刪除在同一次呼叫完成；`shortcut` 必須是已經 normalize 過的儲存值。
    func apply(add: [(phrase: String, shortcut: String)], remove: [Entry],
               completion: @escaping (Error?) -> Void) {
        if add.isEmpty && remove.isEmpty {
            completion(nil)
            return
        }
        let selector = NSSelectorFromString("addEntries:removeEntries:withCompletionHandler:")
        guard let client, client.responds(to: selector),
              let entryClass = NSClassFromString("_KSTextReplacementEntry") as? NSObject.Type
        else {
            completion(StoreError.unavailable)
            return
        }

        func makeEntry(phrase: String, shortcut: String) -> NSObject {
            let entry = entryClass.init()
            entry.setValue(phrase, forKey: "phrase")
            entry.setValue(shortcut, forKey: "shortcut")
            entry.setValue(Date(), forKey: "timestamp")
            return entry
        }

        let adds = add.map { makeEntry(phrase: $0.phrase, shortcut: $0.shortcut) }
        let removes = remove.map { makeEntry(phrase: $0.phrase, shortcut: $0.shortcut) }

        typealias Handler = @convention(block) (AnyObject?) -> Void
        typealias Function = @convention(c) (AnyObject, Selector, NSArray, NSArray, Handler) -> Void
        let function = unsafeBitCast(client.method(for: selector), to: Function.self)

        // 系統即使成功也會回傳 Code=0 的 error，所以 Code=0 時改用重新讀取資料庫來確認結果。
        let handler: Handler = { result in
            DispatchQueue.main.async {
                if let error = result as? NSError, error.code != 0 {
                    completion(StoreError.failed(Self.message(for: error)))
                } else {
                    self.verify(add: add, remove: remove, attempt: 0, completion: completion)
                }
            }
        }
        function(client, selector, adds as NSArray, removes as NSArray, handler)
    }

    /// Code 11 是批次失敗，實際原因在 userInfo 裡的個別錯誤。
    private static func message(for error: NSError) -> String {
        let inner = (error.userInfo["_KSTextReplacementUpdateDidFailErrorsKey"] as? [NSError] ?? [])
            + (error.userInfo["_KSTextReplacementDeleteDidFailErrorsKey"] as? [NSError] ?? [])
        switch inner.first?.code ?? error.code {
        case 6: return "縮寫不能跟詞一模一樣"
        case 9: return "Mac 的文字替代一定要有縮寫"
        default: return "系統拒絕這次寫入（代碼 \(inner.first?.code ?? error.code)）"
        }
    }

    private func verify(add: [(phrase: String, shortcut: String)], remove: [Entry], attempt: Int,
                        completion: @escaping (Error?) -> Void) {
        // 新增會立即寫入資料庫，刪除要等一到數秒才落地。等刪除也落地再回報，
        // 否則緊接著加回同一組詞與縮寫時，會被還在排隊的刪除一起刪掉。
        // 等到上限時只要新增已寫入就算成功，刪除的項目由 AppModel 先隱藏。
        let keys = Set(((try? fetchAll()) ?? []).map(\.key))
        let addKeys = Set(add.map { Entry.makeKey(shortcut: $0.shortcut, phrase: $0.phrase) })
        let added = addKeys.isSubset(of: keys)
        let removed = remove.allSatisfy { !keys.contains($0.key) || addKeys.contains($0.key) }
        if added && (removed || attempt >= 50) {
            completion(nil)
        } else if attempt < 50 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.verify(add: add, remove: remove, attempt: attempt + 1, completion: completion)
            }
        } else {
            completion(StoreError.failed("系統沒有完成這次寫入，請稍後再試"))
        }
    }
}
