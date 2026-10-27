import AppKit

enum UninstallMode: String, CaseIterable {
    case keep, mine, restore
}

enum Installer {
    static let bundleName = "ㄅㄆㄇ字詞庫.app"
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    static let pbs = "/System/Library/CoreServices/pbs"

    static var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").appendingPathComponent(bundleName)
    }

    /// 舊版名稱「注音字詞」的安裝位置，安裝或卸載時一併移除。
    static var legacyURL: URL {
        installedURL.deletingLastPathComponent().appendingPathComponent("注音字詞.app")
    }

    static var isInApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path == installedURL.standardizedFileURL.path
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func registerServices(app: URL = Bundle.main.bundleURL) {
        run(lsregister, ["-f", app.path])
        run(pbs, ["-update"])
        NSUpdateDynamicServices()
    }

    static func serviceRegistered() -> Bool {
        run(pbs, ["-dump"]).contains("NSMessage = addWord;")
    }

    static let justInstalledFlag = "--just-installed"

    /// 從 DMG 或建置資料夾打開時自動安裝；開發時可設 ZHUYINDICT_NO_AUTOINSTALL=1 略過。
    static var shouldAutoInstall: Bool {
        !isInApplications && ProcessInfo.processInfo.environment["ZHUYINDICT_NO_AUTOINSTALL"] == nil
    }

    /// 把自己複製到 ~/Applications 並改由那份啟動；從 DMG 打開的話，結束後退出 DMG。
    static func installCopyAndRelaunch() throws {
        let fm = FileManager.default
        // 更新時先結束已安裝、正在執行的舊版。
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app != .current {
            app.terminate()
        }
        try fm.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: installedURL.path) {
            try fm.removeItem(at: installedURL)
        }
        try fm.copyItem(at: Bundle.main.bundleURL, to: installedURL)
        // 使用者已在 DMG 那份按過「強制打開」，安裝的那份不再重問。
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", installedURL.path])
        if fm.fileExists(atPath: legacyURL.path) {
            run(lsregister, ["-u", legacyURL.path])
            try? fm.removeItem(at: legacyURL)
        }
        registerServices(app: installedURL)
        ejectDiskImageLater()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [justInstalledFlag]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: installedURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// 找出裝著本 App 的 DMG 磁碟區，等這個行程結束後退出。
    /// 從 DMG 打開的 App 可能被系統搬到隨機路徑執行，所以直接到 /Volumes 找。
    private static func ejectDiskImageLater() {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey], options: [.skipHiddenVolumes]) ?? []
        guard let volume = volumes.first(where: {
            $0.path.hasPrefix("/Volumes/")
                && FileManager.default.fileExists(atPath: $0.appendingPathComponent(bundleName).path)
        }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 3; /usr/bin/hdiutil detach \"$0\" -quiet", volume.path]
        try? process.run()
    }

    /// 卸載時處理字詞資料；App 本身由 `removeAppAndQuit` 或 uninstall.command 移除。
    static func uninstallData(_ mode: UninstallMode, store: ReplacementStore, ledger: Ledger,
                              completion: @escaping (Error?) -> Void) {
        do {
            let current = try store.fetchAll()
            switch mode {
            case .keep:
                completion(nil)
            case .mine:
                let mine = current.filter { ledger.records[$0.key] != nil }
                if !mine.isEmpty { Backups.auto() }
                store.apply(add: [], remove: mine, completion: completion)
            case .restore:
                guard let url = ledger.installBackupURL else {
                    completion(StoreError.failed("找不到安裝前的備份"))
                    return
                }
                let target = try ReplacementStore.read(url: url)
                let targetKeys = Set(target.map(\.key))
                let currentKeys = Set(current.map(\.key))
                var seen = Set<String>()
                // 縮寫跟詞一樣的是 iPhone 同步來的無縮寫詞，Mac 不接受寫回，略過。
                let adds = target.filter {
                    !currentKeys.contains($0.key) && $0.shortcut != $0.phrase && seen.insert($0.key).inserted
                }
                    .map { (phrase: $0.phrase, shortcut: $0.shortcut) }
                let removes = current.filter { !targetKeys.contains($0.key) }
                Backups.auto()
                store.apply(add: adds, remove: removes, completion: completion)
            }
        } catch {
            completion(error)
        }
    }

    /// 結束後由背景 shell 移除 App 與記錄；備份資料夾保留。
    static func removeAppAndQuit() {
        var lines = ["sleep 1"]
        for app in [installedURL, legacyURL] where FileManager.default.fileExists(atPath: app.path) {
            lines.append("'\(lsregister)' -u '\(app.path)'")
            lines.append("rm -rf '\(app.path)'")
        }
        lines.append("rm -f '\(Ledger.url.path)'")
        lines.append("'\(pbs)' -update")
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("zhuyindict-uninstall.sh")
        try? lines.joined(separator: "\n").write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: 給 install.command / uninstall.command 呼叫

    static func cliInstall() -> Int32 {
        var ledger = Ledger.load()
        do {
            try Backups.ensureInstallBackup(&ledger)
        } catch {
            print("✗ 安裝前備份失敗：\(error.localizedDescription)")
            return 1
        }
        print("✓ 安裝前備份：\(ledger.installBackup ?? "")")
        registerServices()
        print(serviceRegistered() ? "✓ 右鍵服務已註冊" : "△ 右鍵服務尚未出現，登出再登入後通常就會生效")
        return 0
    }

    static func cliUninstall(_ rawMode: String) -> Int32 {
        guard let mode = UninstallMode(rawValue: rawMode) else {
            print("✗ 不認得的選項：\(rawMode)")
            return 1
        }
        var result: Error?
        var finished = false
        uninstallData(mode, store: ReplacementStore(), ledger: Ledger.load()) { error in
            result = error
            finished = true
        }
        let deadline = Date().addingTimeInterval(30)
        while !finished && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if let result {
            print("✗ \(result.localizedDescription)")
            return 1
        }
        guard finished else {
            print("✗ 系統沒有回應")
            return 1
        }
        run(lsregister, ["-u", Bundle.main.bundlePath])
        try? FileManager.default.removeItem(at: Ledger.url)
        switch mode {
        case .keep: print("✓ 字詞全部保留")
        case .mine: print("✓ 已刪除本程式加入的字詞")
        case .restore: print("✓ 已還原到安裝前的備份")
        }
        return 0
    }
}
