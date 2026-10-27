import AppKit
import UniformTypeIdentifiers

enum SourceFilter: String, CaseIterable, Identifiable {
    case all, manual, service, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .manual: return "自建"
        case .service: return "右鍵加入"
        case .system: return "系統原有"
        }
    }

    var title: String { self == .all ? "全部字詞" : label }
}

struct Row: Identifiable {
    let entry: Entry
    let sourceLabel: String
    var id: String { entry.id }
    var phrase: String { entry.phrase }
    var shortcut: String { entry.displayShortcut }
    var date: Date { entry.date }
}

struct Banner: Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

final class AppModel: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var ledger = Ledger.load()
    @Published var filter: SourceFilter = .all
    @Published var search = ""
    @Published var selection = Set<String>()
    @Published var newToken = 0
    @Published var banner: Banner?
    @Published var pendingDelete: [Entry] = []
    @Published private(set) var lastBackup: Date?

    let store = ReplacementStore()
    /// 已送出刪除、但系統還沒寫進資料庫的項目。
    private var hiddenKeys = Set<String>()

    init() {
        try? Backups.ensureInstallBackup(&ledger)
        reload()
    }

    func reload() {
        do {
            let fetched = try store.fetchAll()
            hiddenKeys.formIntersection(fetched.map(\.key))
            entries = fetched.filter { !hiddenKeys.contains($0.key) }
            selection = selection.filter { id in entries.contains { $0.id == id } }
        } catch {
            flash(error.localizedDescription, isError: true)
        }
        ledger = Ledger.load()
        lastBackup = Backups.latestDate()
    }

    // MARK: 顯示

    func source(of entry: Entry) -> Source {
        ledger.records[entry.key]?.source ?? .system
    }

    func count(_ filter: SourceFilter) -> Int {
        entries.filter { matches($0, filter) }.count
    }

    var mineCount: Int { entries.filter { ledger.records[$0.key] != nil }.count }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: Installer.installedURL.path) }

    func rows(sortedBy order: [KeyPathComparator<Row>]) -> [Row] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return entries
            .filter { matches($0, filter) }
            .filter { query.isEmpty || $0.phrase.contains(query) || $0.displayShortcut.contains(query) }
            .map { Row(entry: $0, sourceLabel: source(of: $0).label) }
            .sorted(using: order)
    }

    var selectedEntries: [Entry] { entries.filter { selection.contains($0.id) } }

    func conflictNote(shortcut: String, phrase: String, excluding: Entry?) -> String? {
        let code = shortcut.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return nil }
        let others = entries.filter {
            $0.displayShortcut == code && $0.phrase != phrase && $0.id != excluding?.id
        }
        guard !others.isEmpty else { return nil }
        let names = others.prefix(3).map(\.phrase).joined(separator: "」「")
        return "\(code) 也用於「\(names)」，打縮寫時會一起列在候選字。"
    }

    private func matches(_ entry: Entry, _ filter: SourceFilter) -> Bool {
        switch filter {
        case .all: return true
        case .manual: return source(of: entry) == .manual
        case .service: return source(of: entry) == .service
        case .system: return source(of: entry) == .system
        }
    }

    // MARK: 寫入

    func startNew() {
        selection = []
        newToken += 1
    }

    func save(phrase rawPhrase: String, shortcut rawShortcut: String, editing: Entry?, source: Source,
              done: @escaping (Bool) -> Void) {
        let phrase = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcut = rawShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else {
            flash("先輸入要加入的詞", isError: true)
            done(false)
            return
        }
        guard let stored = Self.resolveShortcut(shortcut, phrase: phrase) else {
            flash("這個詞沒辦法自動產生縮寫，填一個縮寫就能儲存", isError: true)
            done(false)
            return
        }
        let newKey = Entry.makeKey(shortcut: stored, phrase: phrase)
        if let editing, editing.key == newKey {
            done(true)
            return
        }
        // 剛刪掉的同一組詞與縮寫還沒從系統落地，馬上加回去可能被那筆刪除一起刪掉。
        if hiddenKeys.contains(newKey) {
            flash("這組詞和縮寫剛刪除，系統還在同步，幾秒後再儲存一次", isError: true)
            done(false)
            return
        }
        if entries.contains(where: { $0.key == newKey && $0.id != editing?.id }) {
            flash("「\(phrase)」已經在清單裡", isError: true)
            done(false)
            return
        }

        Backups.auto()
        store.apply(add: [(phrase, stored)], remove: editing.map { [$0] } ?? []) { [weak self] error in
            guard let self else { return }
            if let error {
                self.flash(error.localizedDescription, isError: true)
                done(false)
                return
            }
            // 編輯系統原有的詞不會變成本程式加入的，卸載時才不會誤刪。
            if let editing {
                if let old = self.ledger.records.removeValue(forKey: editing.key) {
                    self.ledger.records[newKey] = Ledger.Record(source: old.source, added: old.added)
                }
            } else {
                self.ledger.records[newKey] = Ledger.Record(source: source, added: Date())
            }
            self.ledger.save()
            self.hide(removed: editing.map { [$0] } ?? [], added: [newKey])
            self.reload()
            self.flash("已儲存「\(phrase)」")
            done(true)
        }
    }

    /// Mac 的文字替代不接受空白縮寫，也不接受跟詞一樣的縮寫；留白時改用聲母首字，
    /// 沒有漢字時用每個英文字的字首（On my way → omw）。
    static func resolveShortcut(_ shortcut: String, phrase: String) -> String? {
        if !shortcut.isEmpty { return shortcut == phrase ? nil : shortcut }
        var auto = Zhuyin.shortcut(for: Zhuyin.analyze(phrase), choices: [:])
        if auto.isEmpty {
            auto = phrase.split(whereSeparator: { $0.isWhitespace })
                .compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }
                .map { String($0).lowercased() }
                .joined()
        }
        return auto.isEmpty || auto == phrase ? nil : auto
    }

    func requestDelete(_ ids: Set<String>) {
        pendingDelete = entries.filter { ids.contains($0.id) }
    }

    func confirmDelete() {
        let targets = pendingDelete
        pendingDelete = []
        guard !targets.isEmpty else { return }
        Backups.auto()
        store.apply(add: [], remove: targets) { [weak self] error in
            guard let self else { return }
            if let error {
                self.flash(error.localizedDescription, isError: true)
                return
            }
            for entry in targets { self.ledger.records.removeValue(forKey: entry.key) }
            self.ledger.save()
            self.selection = []
            self.hide(removed: targets)
            self.reload()
            self.flash("已刪除 \(targets.count) 筆")
        }
    }

    private func hide(removed: [Entry], added: [String] = []) {
        hiddenKeys.formUnion(Set(removed.map(\.key)).subtracting(added))
        hiddenKeys.subtract(added)
        for delay in [2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.reload() }
        }
    }

    func flash(_ text: String, isError: Bool = false) {
        let banner = Banner(text: text, isError: isError)
        self.banner = banner
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.banner == banner { self?.banner = nil }
        }
    }

    // MARK: 匯入／匯出

    func exportPlist() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Text Substitutions.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let items = entries.map { ["phrase": $0.phrase, "shortcut": $0.shortcut] }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: items, format: .xml, options: 0)
            try data.write(to: url)
            flash("已匯出 \(items.count) 筆")
        } catch {
            flash("匯出失敗", isError: true)
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "注音字詞.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func quote(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let lines = ["詞,縮寫"] + entries.map { "\(quote($0.phrase)),\(quote($0.displayShortcut))" }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            flash("已匯出 \(entries.count) 筆")
        } catch {
            flash("匯出失敗", isError: true)
        }
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList, .commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let pairs = url.pathExtension.lowercased() == "csv" ? Self.parseCSV(url) : Self.parsePlist(url)
        let existing = Set(entries.map(\.key))
        var seen = Set<String>()
        let adds = pairs.compactMap { pair -> (phrase: String, shortcut: String)? in
            let phrase = pair.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { return nil }
            guard let stored = Self.resolveShortcut(pair.shortcut.trimmingCharacters(in: .whitespaces),
                                                    phrase: phrase) else { return nil }
            let key = Entry.makeKey(shortcut: stored, phrase: phrase)
            guard !existing.contains(key), seen.insert(key).inserted else { return nil }
            return (phrase, stored)
        }
        guard !adds.isEmpty else {
            flash("沒有新的字詞要匯入")
            return
        }
        Backups.auto()
        store.apply(add: adds, remove: []) { [weak self] error in
            guard let self else { return }
            if let error {
                self.flash(error.localizedDescription, isError: true)
                return
            }
            for add in adds {
                self.ledger.records[Entry.makeKey(shortcut: add.shortcut, phrase: add.phrase)] =
                    Ledger.Record(source: .manual, added: Date())
            }
            self.ledger.save()
            self.reload()
            self.flash("已匯入 \(adds.count) 筆")
        }
    }

    private static func parsePlist(_ url: URL) -> [(phrase: String, shortcut: String)] {
        guard let data = try? Data(contentsOf: url),
              let items = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return [] }
        return items.compactMap { item in
            guard let phrase = item["phrase"] as? String else { return nil }
            return (phrase, item["shortcut"] as? String ?? "")
        }
    }

    private static func parseCSV(_ url: URL) -> [(phrase: String, shortcut: String)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).dropFirst().compactMap { line in
            let fields = splitCSV(line)
            guard let phrase = fields.first, !phrase.isEmpty else { return nil }
            return (phrase, fields.count > 1 ? fields[1] : "")
        }
    }

    private static func splitCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            if c == "\"" {
                if inQuotes, chars.first == "\"" {
                    current.append("\"")
                    chars.removeFirst()
                } else {
                    inQuotes.toggle()
                }
            } else if c == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        fields.append(current)
        return fields
    }
}
