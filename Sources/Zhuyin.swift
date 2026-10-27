import Foundation

/// 產生聲母首字縮寫：快到了 → ㄎㄉㄌ；沒有聲母的字取第一個注音符號（銀 → ㄧ）。
enum Zhuyin {
    struct Slot {
        let char: Character
        /// 系統預設讀音的首個注音符號；非漢字為 nil。
        let initial: String?
        /// 首個注音符號不同的破音字讀音；一般字為空。
        let options: [String]
        let defaultIndex: Int

        var isPolyphone: Bool { !options.isEmpty }
    }

    static func analyze(_ phrase: String) -> [Slot] {
        phrase.map { char in
            guard isHan(char) else {
                return Slot(char: char, initial: nil, options: [], defaultIndex: 0)
            }
            let initial = pinyinInitial(of: char)
            if let options = polyphones[char] {
                let index = options.firstIndex { String($0.prefix(1)) == initial } ?? 0
                return Slot(char: char, initial: initial, options: options, defaultIndex: index)
            }
            return Slot(char: char, initial: initial, options: [], defaultIndex: 0)
        }
    }

    static func shortcut(for slots: [Slot], choices: [Int: Int]) -> String {
        slots.enumerated().compactMap { index, slot -> String? in
            if slot.isPolyphone {
                return String(slot.options[choices[index] ?? slot.defaultIndex].prefix(1))
            }
            return slot.initial
        }.joined()
    }

    private static func isHan(_ char: Character) -> Bool {
        char.unicodeScalars.count == 1 && char.unicodeScalars.first!.properties.isUnifiedIdeograph
    }

    private static func pinyinInitial(of char: Character) -> String? {
        let text = NSMutableString(string: String(char))
        CFStringTransform(text, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(text, nil, kCFStringTransformStripDiacritics, false)
        let syllable = (text as String).lowercased().trimmingCharacters(in: .whitespaces)
        guard let first = syllable.first, first.isASCII, first.isLetter else { return nil }
        return initial(ofPinyin: syllable)
    }

    private static let consonants: [(String, String)] = [
        ("zh", "ㄓ"), ("ch", "ㄔ"), ("sh", "ㄕ"),
        ("b", "ㄅ"), ("p", "ㄆ"), ("m", "ㄇ"), ("f", "ㄈ"),
        ("d", "ㄉ"), ("t", "ㄊ"), ("n", "ㄋ"), ("l", "ㄌ"),
        ("g", "ㄍ"), ("k", "ㄎ"), ("h", "ㄏ"),
        ("j", "ㄐ"), ("q", "ㄑ"), ("x", "ㄒ"),
        ("r", "ㄖ"), ("z", "ㄗ"), ("c", "ㄘ"), ("s", "ㄙ"),
    ]

    private static let vowels: [(String, String)] = [
        ("ang", "ㄤ"), ("ai", "ㄞ"), ("an", "ㄢ"), ("ao", "ㄠ"), ("a", "ㄚ"),
        ("ou", "ㄡ"), ("o", "ㄛ"),
        ("eng", "ㄥ"), ("ei", "ㄟ"), ("en", "ㄣ"), ("e", "ㄜ"),
    ]

    private static func initial(ofPinyin syllable: String) -> String? {
        if let match = consonants.first(where: { syllable.hasPrefix($0.0) }) { return match.1 }
        if syllable.hasPrefix("y") {
            return syllable.hasPrefix("yu") || syllable == "yong" ? "ㄩ" : "ㄧ"
        }
        if syllable.hasPrefix("w") { return "ㄨ" }
        if syllable.hasPrefix("er") { return "ㄦ" }
        return vowels.first(where: { syllable.hasPrefix($0.0) })?.1
    }

    /// 只收首個注音符號不同的讀音；只差聲調或韻母的破音字不影響縮寫，所以不列。
    private static let polyphones: [Character: [String]] = [
        "行": ["ㄒㄧㄥˊ", "ㄏㄤˊ"],
        "長": ["ㄔㄤˊ", "ㄓㄤˇ"],
        "重": ["ㄓㄨㄥˋ", "ㄔㄨㄥˊ"],
        "樂": ["ㄌㄜˋ", "ㄩㄝˋ"],
        "會": ["ㄏㄨㄟˋ", "ㄎㄨㄞˋ"],
        "調": ["ㄉㄧㄠˋ", "ㄊㄧㄠˊ"],
        "傳": ["ㄔㄨㄢˊ", "ㄓㄨㄢˋ"],
        "藏": ["ㄘㄤˊ", "ㄗㄤˋ"],
        "參": ["ㄘㄢ", "ㄕㄣ"],
        "降": ["ㄐㄧㄤˋ", "ㄒㄧㄤˊ"],
        "校": ["ㄒㄧㄠˋ", "ㄐㄧㄠˋ"],
        "便": ["ㄅㄧㄢˋ", "ㄆㄧㄢˊ"],
        "朝": ["ㄓㄠ", "ㄔㄠˊ"],
        "單": ["ㄉㄢ", "ㄕㄢˋ"],
        "曾": ["ㄘㄥˊ", "ㄗㄥ"],
        "沈": ["ㄕㄣˇ", "ㄔㄣˊ"],
        "解": ["ㄐㄧㄝˇ", "ㄒㄧㄝˋ"],
        "差": ["ㄔㄚ", "ㄘ"],
        "給": ["ㄍㄟˇ", "ㄐㄧˇ"],
        "殼": ["ㄎㄜˊ", "ㄑㄧㄠˋ"],
        "似": ["ㄙˋ", "ㄕˋ"],
        "盛": ["ㄕㄥˋ", "ㄔㄥˊ"],
        "省": ["ㄕㄥˇ", "ㄒㄧㄥˇ"],
        "宿": ["ㄙㄨˋ", "ㄒㄧㄡˇ"],
        "色": ["ㄙㄜˋ", "ㄕㄞˇ"],
        "率": ["ㄕㄨㄞˋ", "ㄌㄩˋ"],
        "畜": ["ㄔㄨˋ", "ㄒㄩˋ"],
        "茄": ["ㄑㄧㄝˊ", "ㄐㄧㄚ"],
        "車": ["ㄔㄜ", "ㄐㄩ"],
        "乾": ["ㄍㄢ", "ㄑㄧㄢˊ"],
        "區": ["ㄑㄩ", "ㄡ"],
        "期": ["ㄑㄧˊ", "ㄐㄧ"],
        "奇": ["ㄑㄧˊ", "ㄐㄧ"],
        "繫": ["ㄒㄧˋ", "ㄐㄧˋ"],
        "卡": ["ㄎㄚˇ", "ㄑㄧㄚˇ"],
        "囤": ["ㄉㄨㄣˋ", "ㄊㄨㄣˊ"],
        "蔓": ["ㄇㄢˋ", "ㄨㄢˋ"],
        "秘": ["ㄇㄧˋ", "ㄅㄧˋ"],
        "識": ["ㄕˋ", "ㄓˋ"],
        "屏": ["ㄆㄧㄥˊ", "ㄅㄧㄥˇ"],
        "扁": ["ㄅㄧㄢˇ", "ㄆㄧㄢ"],
        "番": ["ㄈㄢ", "ㄆㄢ"],
        "否": ["ㄈㄡˇ", "ㄆㄧˇ"],
        "仇": ["ㄔㄡˊ", "ㄑㄧㄡˊ"],
        "尉": ["ㄨㄟˋ", "ㄩˋ"],
        "弄": ["ㄋㄨㄥˋ", "ㄌㄨㄥˋ"],
        "嚇": ["ㄒㄧㄚˋ", "ㄏㄜˋ"],
        "咳": ["ㄎㄜˊ", "ㄏㄞ"],
        "剎": ["ㄔㄚˋ", "ㄕㄚ"],
        "廈": ["ㄒㄧㄚˋ", "ㄕㄚˋ"],
        "合": ["ㄏㄜˊ", "ㄍㄜˇ"],
        "夾": ["ㄐㄧㄚˊ", "ㄍㄚ"],
        "臭": ["ㄔㄡˋ", "ㄒㄧㄡˋ"],
    ]
}

/// 新增／編輯表單的草稿：輸入詞時自動更新縮寫，直到使用者自己改過縮寫。
final class WordDraft: ObservableObject {
    @Published var phrase: String {
        didSet { if phrase != oldValue { recompute() } }
    }
    @Published private(set) var shortcut: String
    @Published private(set) var choices: [Int: Int] = [:]
    @Published private(set) var slots: [Zhuyin.Slot] = []
    private var shortcutTouched: Bool

    init(phrase: String, shortcut: String? = nil) {
        self.phrase = phrase
        self.shortcut = shortcut ?? ""
        self.shortcutTouched = shortcut != nil
        recompute()
    }

    var polyphoneIndices: [Int] { slots.indices.filter { slots[$0].isPolyphone } }

    /// 縮寫留白時儲存會用到的值，拿來當欄位提示。
    var fallbackShortcut: String {
        AppModel.resolveShortcut("", phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    func setShortcut(_ value: String) {
        guard value != shortcut else { return }
        shortcut = value
        shortcutTouched = true
    }

    func choose(slot: Int, option: Int) {
        choices[slot] = option
        shortcutTouched = false
        recompute()
    }

    private func recompute() {
        let newSlots = Zhuyin.analyze(phrase)
        choices = choices.filter { index, option in
            index < newSlots.count && newSlots[index].options.indices.contains(option)
                && index < slots.count && slots[index].char == newSlots[index].char
        }
        slots = newSlots
        if !shortcutTouched {
            shortcut = Zhuyin.shortcut(for: slots, choices: choices)
        }
    }
}
