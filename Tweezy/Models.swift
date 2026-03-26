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
    var isPinned: Bool
    var appName: String?

    init(id: UUID = UUID(), content: ClipboardContent, copiedAt: Date = Date(),
         tagIDs: [UUID] = [], isPinned: Bool = false, appName: String? = nil) {
        self.id = id; self.content = content; self.copiedAt = copiedAt
        self.tagIDs = tagIDs; self.isPinned = isPinned; self.appName = appName
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
        return result.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.copiedAt > b.copiedAt
        }
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

    func togglePin(_ item: ClipboardItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPinned.toggle(); save()
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general; pb.clearContents()
        switch item.content {
        case .text(let s): pb.setString(s, forType: .string)
        case .image(let d): if let img = NSImage(data: d) { pb.writeObjects([img]) }
        }
    }

    func clearAll() { items.removeAll { !$0.isPinned }; save() }

    private func trim() {
        let unpinned = items.filter { !$0.isPinned }
        if unpinned.count > 100 {
            let excess = unpinned.suffix(unpinned.count - 100)
            items.removeAll { item in excess.contains(where: { $0.id == item.id }) }
        }
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
