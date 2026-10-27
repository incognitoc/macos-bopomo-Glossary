import SwiftUI

// MARK: 設計規範：8pt 網格、字級 12/14/16/20/24、品牌色只給主要按鈕
// Liquid Glass：玻璃只用在浮在內容上的導覽與控制層（側欄、編輯面板、按鈕、提示），
// 清單內容維持白底；玻璃上不再疊玻璃，圓角與視窗同心（外距 8、圓角 16）。

enum Theme {
    static let brand = Color(red: 0.11, green: 0.42, blue: 0.55)
    static let field = Color.primary.opacity(0.06)
    static let panelInset: CGFloat = 8
    static let panelRadius: CGFloat = 16
}

/// 膠囊形玻璃按鈕；`tint` 只給主要按鈕用品牌色。
struct GlassButtonStyle: ButtonStyle {
    var tint: Color?
    var foreground: Color = .primary
    var weight: Font.Weight = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                // 舊 SDK 下系統對玻璃的 tint 很淡，品牌色另外鋪一層才看得清楚白字。
                ZStack {
                    GlassBackground(cornerRadius: 16)
                    if let tint { Capsule().fill(tint.opacity(0.92)) }
                }
            }
            .fixedSize()
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var primaryGlass: GlassButtonStyle { GlassButtonStyle(tint: Theme.brand, foreground: .white, weight: .medium) }
    static var secondaryGlass: GlassButtonStyle { GlassButtonStyle() }
    static var destructiveGlass: GlassButtonStyle { GlassButtonStyle(foreground: .red, weight: .medium) }
}

/// 玻璃面板裡的輸入框用淡灰底，不再疊一層玻璃。
struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: 主視窗

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showInstall = false

    var body: some View {
        // 視窗內容延伸到標題列下方，側欄與編輯面板是浮在白色清單上的玻璃。
        HStack(spacing: 0) {
            Sidebar(model: model, showInstall: $showInstall)
                .frame(width: 216)
                .background(GlassBackground(cornerRadius: Theme.panelRadius))
                .padding(Theme.panelInset)
            ListZone(model: model)
                .frame(minWidth: 400)
            EditorZone(model: model)
                .frame(width: 312)
                .background(GlassBackground(cornerRadius: Theme.panelRadius))
                .padding(Theme.panelInset)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .ignoresSafeArea()
        .frame(minWidth: 960, minHeight: 560)
        .sheet(isPresented: $showInstall) {
            InstallView(model: model, isPresented: $showInstall)
        }
        .confirmationDialog(
            "刪除 \(model.pendingDelete.count) 筆字詞？",
            isPresented: Binding(get: { !model.pendingDelete.isEmpty },
                                 set: { if !$0 { model.pendingDelete = [] } })
        ) {
            Button("刪除", role: .destructive) { model.confirmDelete() }
            Button("取消", role: .cancel) { model.pendingDelete = [] }
        } message: {
            Text("會從系統的文字替代一起刪除，iCloud 同步的裝置也會跟著刪除。")
        }
    }
}

struct Sidebar: View {
    @ObservedObject var model: AppModel
    @Binding var showInstall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Zhuyin Words").font(.system(size: 20, weight: .semibold))
                Text("注音字詞・讓常用字不再被忘記").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(16)
            .padding(.top, 32)

            Text("篩選")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(SourceFilter.allCases) { filter in
                    Button {
                        model.filter = filter
                    } label: {
                        HStack {
                            Text(filter.label)
                            Spacer()
                            Text("\(model.count(filter))").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 14))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(model.filter == filter ? Color.primary.opacity(0.08) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.isInstalled ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(model.isInstalled ? "已安裝" : "尚未安裝到應用程式").font(.system(size: 12))
                }
                if let date = model.lastBackup {
                    Text("上次備份 \(date.formatted(date: .numeric, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Button("安裝與卸載…") { showInstall = true }
                    .buttonStyle(.secondaryGlass)
                    .padding(.top, 8)
            }
            .padding(16)
        }
    }
}

struct ListZone: View {
    @ObservedObject var model: AppModel
    @State private var sortOrder = [KeyPathComparator(\Row.date, order: .reverse)]

    var body: some View {
        let rows = model.rows(sortedBy: sortOrder)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(model.filter.title)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize()
                    Spacer(minLength: 16)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜尋詞或注音", text: $model.search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(GlassBackground(cornerRadius: 16))
                    .frame(minWidth: 168, maxWidth: 200)
                    Menu("匯入／匯出") {
                        Button("匯入 plist 或 CSV…") { model.importFile() }
                        Divider()
                        Button("匯出 plist（可拖進系統設定）…") { model.exportPlist() }
                        Button("匯出 CSV…") { model.exportCSV() }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(GlassBackground(cornerRadius: 16))
                    Button {
                        model.startNew()
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                    .buttonStyle(.secondaryGlass)
                }
                Text("\(rows.count) 筆・在任何 App 反白文字，按右鍵 › 服務 › 加入注音字詞")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
            .padding(.bottom, 16)

            Divider()

            Table(rows, selection: $model.selection, sortOrder: $sortOrder) {
                TableColumn("詞", value: \.phrase) { row in
                    Text(row.phrase).font(.system(size: 14))
                }
                TableColumn("縮寫", value: \.shortcut) { row in
                    Text(row.shortcut.isEmpty ? "—" : row.shortcut)
                        .font(.system(size: 14))
                        .foregroundStyle(row.shortcut.isEmpty ? .secondary : .primary)
                }
                .width(min: 72, ideal: 96)
                TableColumn("來源", value: \.sourceLabel) { row in
                    Text(row.sourceLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .width(min: 64, ideal: 80)
                TableColumn("加入", value: \.date) { row in
                    Text(row.date.formatted(date: .numeric, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 96)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if !ids.isEmpty {
                    Button("刪除 \(ids.count) 筆…", role: .destructive) { model.requestDelete(ids) }
                }
            }
            .onDeleteCommand { model.requestDelete(model.selection) }
        }
        .overlay(alignment: .bottom) {
            if let banner = model.banner {
                HStack(spacing: 8) {
                    Image(systemName: banner.isError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(banner.isError ? Color.red : Color.green)
                    Text(banner.text)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(GlassBackground(cornerRadius: 16))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.banner)
    }
}

struct EditorZone: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let selected = model.selectedEntries
        Group {
            if selected.count > 1 {
                MultiSelection(model: model, count: selected.count)
            } else {
                EntryEditor(model: model, editing: selected.first)
                    .id(selected.first?.id ?? "new-\(model.newToken)")
            }
        }
        .padding(.top, 24)
    }
}

struct MultiSelection: View {
    @ObservedObject var model: AppModel
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "已選 \(count) 筆", subtitle: "可以一次刪除，或按新增回到新增模式。")
            Spacer()
            HStack(spacing: 8) {
                Button("刪除 \(count) 筆") { model.requestDelete(model.selection) }
                    .buttonStyle(.destructiveGlass)
                Spacer()
                Button("新增") { model.startNew() }
                    .buttonStyle(.secondaryGlass)
            }
        }
        .padding(24)
    }
}

struct EntryEditor: View {
    @ObservedObject var model: AppModel
    let editing: Entry?
    @StateObject private var draft: WordDraft
    @FocusState private var phraseFocused: Bool

    init(model: AppModel, editing: Entry?) {
        self.model = model
        self.editing = editing
        _draft = StateObject(wrappedValue: WordDraft(phrase: editing?.phrase ?? "",
                                                     shortcut: editing?.displayShortcut))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: editing == nil ? "新增字詞" : "編輯字詞",
                subtitle: editing == nil
                    ? "輸入常用的詞，縮寫會用聲母首字自動產生；刪掉留白也能儲存。"
                    : "修改後按儲存，系統的文字替代會一起更新。"
            )
            .padding(.bottom, 24)

            WordForm(model: model, draft: draft, excluding: editing, phraseFocus: $phraseFocused)

            Spacer(minLength: 24)

            HStack(spacing: 8) {
                if let editing {
                    Button("刪除") { model.requestDelete([editing.id]) }
                        .buttonStyle(.destructiveGlass)
                }
                Spacer()
                if editing != nil {
                    Button("取消") { model.startNew() }
                        .buttonStyle(.secondaryGlass)
                }
                Button("儲存", action: save)
                    .buttonStyle(.primaryGlass)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear {
            if editing == nil { phraseFocused = true }
        }
    }

    private func save() {
        model.save(phrase: draft.phrase, shortcut: draft.shortcut, editing: editing, source: .manual) { ok in
            if ok && editing == nil { model.startNew() }
        }
    }
}

struct WordForm: View {
    @ObservedObject var model: AppModel
    @ObservedObject var draft: WordDraft
    let excluding: Entry?
    var phraseFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("詞") {
                TextField("鼎泰豐", text: $draft.phrase)
                    .focused(phraseFocus)
            }
            field("縮寫（聲母首字，可留白）") {
                TextField(draft.fallbackShortcut.isEmpty ? "留白" : "留白時用 \(draft.fallbackShortcut)",
                          text: Binding(get: { draft.shortcut }, set: { draft.setShortcut($0) }))
            }
            ForEach(draft.polyphoneIndices, id: \.self) { index in
                let slot = draft.slots[index]
                field("破音字「\(String(slot.char))」") {
                    Picker("", selection: Binding(get: { draft.choices[index] ?? slot.defaultIndex },
                                                  set: { draft.choose(slot: index, option: $0) })) {
                        ForEach(slot.options.indices, id: \.self) { option in
                            Text(slot.options[option]).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if let note = model.conflictNote(shortcut: draft.shortcut.isEmpty ? draft.fallbackShortcut : draft.shortcut,
                                             phrase: draft.phrase, excluding: excluding) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(note).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            content().modifier(FieldStyle())
        }
    }
}

// MARK: 右鍵加入小視窗

struct AddWordPanel: View {
    @ObservedObject var model: AppModel
    @StateObject private var draft: WordDraft
    @FocusState private var phraseFocused: Bool
    @State private var added = false
    let onClose: () -> Void

    init(model: AppModel, phrase: String, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _draft = StateObject(wrappedValue: WordDraft(phrase: phrase))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if added {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundStyle(.green)
                    Text("已加入「\(draft.phrase)」").font(.system(size: 16))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                PageHeader(title: "加入注音字詞", subtitle: "確認詞和縮寫，按加入就會寫進系統的文字替代。")
                    .padding(.bottom, 24)
                WordForm(model: model, draft: draft, excluding: nil, phraseFocus: $phraseFocused)
                if let banner = model.banner, banner.isError {
                    Text(banner.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.top, 16)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("取消", action: onClose)
                        .buttonStyle(.secondaryGlass)
                        .keyboardShortcut(.cancelAction)
                    Button("加入", action: add)
                        .buttonStyle(.primaryGlass)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 24)
            }
        }
        .padding(24)
        .padding(.top, 16)
        .frame(width: 360)
        .background(GlassBackground(cornerRadius: Theme.panelRadius))
    }

    private func add() {
        model.save(phrase: draft.phrase, shortcut: draft.shortcut, editing: nil, source: .service) { ok in
            guard ok else { return }
            added = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { onClose() }
        }
    }
}

// MARK: 安裝與卸載

struct InstallView: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    @State private var mode: UninstallMode = .keep
    @State private var serviceOK = false
    @State private var confirming = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "安裝與卸載", subtitle: "檢查安裝狀態，或把注音字詞從這台 Mac 移除。")
                .padding(.bottom, 24)

            Text("安裝狀態").font(.system(size: 14, weight: .semibold)).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 8) {
                status(Installer.isInApplications, "App 位於 ~/Applications") {
                    if !Installer.isInApplications {
                        Button("安裝到應用程式") {
                            do { try Installer.installCopyAndRelaunch() } catch { self.error = error.localizedDescription }
                        }
                        .buttonStyle(.secondaryGlass)
                    }
                }
                status(serviceOK, "右鍵服務已註冊") {
                    Button("重新註冊") {
                        Installer.registerServices()
                        serviceOK = Installer.serviceRegistered()
                    }
                    .buttonStyle(.secondaryGlass)
                }
                status(model.ledger.installBackupURL != nil, backupLabel) {
                    Button("打開備份資料夾") { NSWorkspace.shared.open(Backups.dir) }
                        .buttonStyle(.secondaryGlass)
                }
                HStack(spacing: 8) {
                    Image(systemName: "keyboard").foregroundStyle(.secondary).frame(width: 16)
                    Text("快捷鍵（選用）").font(.system(size: 14))
                    Spacer()
                    Button("設定快捷鍵") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                    .buttonStyle(.secondaryGlass)
                }
                Text("在「鍵盤 › 鍵盤快速鍵 › 服務 › 文字」找到「加入注音字詞」，就能指定按鍵。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 24)

            Text("卸載").font(.system(size: 14, weight: .semibold)).padding(.bottom, 8)
            Text("已加入的字詞要怎麼處理？").font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 8)
            Picker("", selection: $mode) {
                Text("保留全部字詞").tag(UninstallMode.keep)
                Text("只刪除本程式加入的 \(model.mineCount) 筆").tag(UninstallMode.mine)
                if model.ledger.installBackupURL != nil {
                    Text("還原到安裝前的備份（\(installDateText)）").tag(UninstallMode.restore)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .font(.system(size: 14))
            Text("備份資料夾會保留在 ~/Library/Application Support/ZhuyinDict/Backups。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red).padding(.top, 16)
            }

            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("完成") { isPresented = false }
                    .buttonStyle(.secondaryGlass)
                    .keyboardShortcut(.cancelAction)
                Button("卸載…") { confirming = true }
                    .buttonStyle(.destructiveGlass)
            }
            .padding(.top, 32)
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { serviceOK = Installer.serviceRegistered() }
        .confirmationDialog("確定要卸載注音字詞？", isPresented: $confirming) {
            Button("卸載", role: .destructive, action: uninstall)
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var installDateText: String {
        model.ledger.installDate?.formatted(date: .numeric, time: .omitted) ?? ""
    }

    private var backupLabel: String {
        model.ledger.installBackupURL == nil ? "安裝前備份" : "安裝前備份（\(installDateText)）"
    }

    private var confirmMessage: String {
        switch mode {
        case .keep: return "App 和右鍵服務會被移除，字詞全部保留。"
        case .mine: return "會刪除本程式加入的 \(model.mineCount) 筆字詞，並移除 App 和右鍵服務。"
        case .restore: return "文字替代會還原成 \(installDateText) 的內容，之後新增的字詞都會消失。"
        }
    }

    private func status<Action: View>(_ ok: Bool, _ label: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle" : "circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
                .frame(width: 16)
            Text(label).font(.system(size: 14))
            Spacer()
            action()
        }
    }

    private func uninstall() {
        working = true
        error = nil
        Installer.uninstallData(mode, store: model.store, ledger: model.ledger) { result in
            working = false
            if let result {
                error = result.localizedDescription
            } else {
                Installer.removeAppAndQuit()
            }
        }
    }
}
