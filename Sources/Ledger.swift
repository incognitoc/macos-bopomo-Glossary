import Foundation

enum Source: String, Codable {
    case manual, service, system

    var label: String {
        switch self {
        case .manual: return "自建"
        case .service: return "右鍵加入"
        case .system: return "系統原有"
        }
    }
}

/// 記錄哪些字詞是本程式加入的，卸載時才分得出來。
struct Ledger: Codable {
    struct Record: Codable {
        var source: Source
        var added: Date
    }

    var records: [String: Record] = [:]
    var installBackup: String?
    var installDate: Date?

    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ZhuyinDict")
    }
    static var url: URL { dir.appendingPathComponent("ledger.json") }

    static func load() -> Ledger {
        guard let data = try? Data(contentsOf: url),
              let ledger = try? JSONDecoder().decode(Ledger.self, from: data)
        else { return Ledger() }
        return ledger
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.url, options: .atomic)
        }
    }

    var installBackupURL: URL? {
        guard let path = installBackup, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

enum Backups {
    static var dir: URL { Ledger.dir.appendingPathComponent("Backups") }
    private static let keepAuto = 20

    @discardableResult
    static func make(prefix: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).db")
        try? FileManager.default.removeItem(at: url)
        try ReplacementStore.backup(to: url)
        return url
    }

    /// 每次寫入前呼叫；只保留最新的 20 份自動備份，安裝前備份不會被清掉。
    static func auto() {
        _ = try? make(prefix: "auto")
        let autos = files().filter { $0.lastPathComponent.hasPrefix("auto-") }
        for old in autos.dropFirst(keepAuto) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    static func latestDate() -> Date? {
        files().first.flatMap { modified($0) }
    }

    static func ensureInstallBackup(_ ledger: inout Ledger) throws {
        guard ledger.installBackupURL == nil else { return }
        ledger.installBackup = try make(prefix: "install").path
        ledger.installDate = Date()
        ledger.save()
    }

    /// 由新到舊排序的 .db 檔。
    private static func files() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "db" }
            .sorted { (modified($0) ?? .distantPast) > (modified($1) ?? .distantPast) }
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
