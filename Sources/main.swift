import AppKit
import SwiftUI

let arguments = CommandLine.arguments
if arguments.contains("--install") {
    exit(Installer.cliInstall())
}
if let index = arguments.firstIndex(of: "--uninstall") {
    exit(Installer.cliUninstall(index + 1 < arguments.count ? arguments[index + 1] : "keep"))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var mainWindow: NSWindow?
    private var panel: NSPanel?
    private var serviceInvoked = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        // 由右鍵服務喚起時只顯示小視窗，不打開主視窗。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !self.serviceInvoked { self.showMain() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func showMain() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "ㄅㄆㄇ字詞庫"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: MainView(model: model))
            host.sizingOptions = [.minSize]
            window.contentView = host
            window.center()
            window.setFrameAutosaveName("MainWindow")
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.model.reload() }
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Info.plist 的 NSServices 指到這裡：反白文字 › 右鍵 › 服務 › 加入ㄅㄆㄇ字詞庫。
    @objc func addWord(_ pasteboard: NSPasteboard, userData: String?,
                       error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        serviceInvoked = true
        let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            error.pointee = "沒有選取文字" as NSString
            return
        }
        showPanel(phrase: String(text.prefix(64)))
    }

    private func showPanel(phrase: String) {
        panel?.close()
        model.reload()
        model.banner = nil
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = "ㄅㄆㄇ字詞庫"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // 整個小視窗就是一片玻璃。
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AddWordPanel(model: model, phrase: phrase) { [weak self] in
            self?.finishPanel()
        })
        panel.center()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// 加入完成後把焦點還給原本的 App。
    private func finishPanel() {
        panel?.close()
        panel = nil
        if mainWindow?.isVisible == true {
            NSApp.hide(nil)
        } else {
            NSApp.terminate(nil)
        }
    }
}

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "關於ㄅㄆㄇ字詞庫", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "隱藏ㄅㄆㄇ字詞庫", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "結束ㄅㄆㄇ字詞庫", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main, title: "ㄅㄆㄇ字詞庫")

        let edit = NSMenu(title: "編輯")
        edit.addItem(withTitle: "還原", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪下", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷貝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "貼上", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main, title: "編輯")

        let window = NSMenu(title: "視窗")
        window.addItem(withTitle: "關閉", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(window, to: main, title: "視窗")

        return main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
