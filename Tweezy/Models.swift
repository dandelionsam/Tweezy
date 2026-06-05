import Foundation
import AppKit

// MARK: - Tag Model

struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String = "#6B7280") {
        self.id = id; self.name = name; self.colorHex = colorHex
    }
}

// MARK: - ClipboardItem Model

enum ClipboardContent: Codable {
    case text(String)
    case image(Data)

    var isText: Bool { if case .text = self { return true }; return false }
}

struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    var content: ClipboardContent
    var copiedAt: Date
    var tagIDs: [UUID]
    var appName: String?

    init(id: UUID = UUID(), content: ClipboardContent, copiedAt: Date = Date(),
         tagIDs: [UUID] = [], appName: String? = nil) {
        self.id = id; self.content = content; self.copiedAt = copiedAt
        self.tagIDs = tagIDs; self.appName = appName
    }

    var previewText: String {
        switch content {
        case .text(let s): return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        case .image: return "📷"
        }
    }
}

// MARK: - ClipboardStore

class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published var items: [ClipboardItem] = []
    @Published var tags: [Tag] = []
    @Published var searchText: String = ""
    @Published var selectedTagID: UUID? = nil
    @Published var matchCase: Bool = false
    @Published var matchWord: Bool = false

    /// Set by copyToClipboard so ClipboardMonitor ignores the self-triggered change
    var skipNextClipboardChange = false

    private let saveURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ClipboardManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("items.json")
    }()

    private init() { load() }

    var filteredItems: [ClipboardItem] {
        var result = items
        if let tagID = selectedTagID {
            result = result.filter { $0.tagIDs.contains(tagID) }
        }
        if !searchText.isEmpty {
            result = result.filter { item in
                guard case .text(let s) = item.content else { return false }
                let needle   = matchCase ? searchText : searchText.lowercased()
                let haystack = matchCase ? s : s.lowercased()
                if matchWord {
                    let pattern = "(?<![\\w])" + NSRegularExpression.escapedPattern(for: needle) + "(?![\\w])"
                    let opts: NSRegularExpression.Options = matchCase ? [] : .caseInsensitive
                    guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else {
                        return haystack.contains(needle)
                    }
                    return regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
                } else {
                    return haystack.contains(needle)
                }
            }
        }
        return result.sorted { $0.copiedAt > $1.copiedAt }
    }

    func add(_ item: ClipboardItem) {
        if case .text(let newText) = item.content {
            if let existing = items.first(where: {
                if case .text(let t) = $0.content { return t == newText }; return false
            }) {
                items.removeAll { $0.id == existing.id }
                var updated = existing; updated.copiedAt = Date()
                items.insert(updated, at: 0); trim(); save(); return
            }
        }
        items.insert(item, at: 0); trim(); save()
    }

    func delete(_ item: ClipboardItem) { items.removeAll { $0.id == item.id }; save() }

    func copyToClipboard(_ item: ClipboardItem) {
        skipNextClipboardChange = true
        let pb = NSPasteboard.general; pb.clearContents()
        switch item.content {
        case .text(let s): pb.setString(s, forType: .string)
        case .image(let d): if let img = NSImage(data: d) { pb.writeObjects([img]) }
        }
    }

    func clearAll() { items.removeAll(); save() }

    private func trim() {
        if items.count > 100 { items = Array(items.prefix(100)) }
    }

    func save() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        }
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(self.items) { try? data.write(to: self.saveURL) }
        }
    }

    func load() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? decoder.decode([ClipboardItem].self, from: data) {
            self.items = loaded
        }
    }
}

// MARK: - SensitiveDataSettings

class SensitiveDataSettings: ObservableObject {
    static let shared = SensitiveDataSettings()

    static let defaultPattern = #"^(?!https?://)(?![/~])(?!.*://)(?=.*[A-Za-z])(?=.*[^A-Za-z\s])[^\s]{8,128}$"#

    @Published var pattern: String {
        didSet { UserDefaults.standard.set(pattern, forKey: "sensitivePattern") }
    }
    @Published var showSensitiveData: Bool {
        didSet { UserDefaults.standard.set(showSensitiveData, forKey: "showSensitiveData") }
    }

    private init() {
        pattern = UserDefaults.standard.string(forKey: "sensitivePattern") ?? Self.defaultPattern
        showSensitiveData = UserDefaults.standard.bool(forKey: "showSensitiveData")
    }

    private var compiledRegex: NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    func isSensitive(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !pattern.isEmpty, let regex = compiledRegex else { return false }
        return regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
}
