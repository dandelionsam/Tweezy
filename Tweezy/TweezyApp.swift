import SwiftUI
import AppKit
import Carbon.HIToolbox
import ApplicationServices
import ServiceManagement

@main
struct TweezyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands { CommandGroup(replacing: .appSettings) {} }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var clipboardMonitor: ClipboardMonitor?
    var hotkeyManager: GlobalHotkeyManager?
    var settingsWindow: NSWindow?
    var tagManagerWindow: NSWindow?
    var shortcutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let img = NSImage(named: "TrayIcon") {
                img.isTemplate = false
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                       accessibilityDescription: NSLocalizedString("accessibility.clipboard_manager", comment: ""))
            }
        }

        statusItem?.menu = buildMenu()

        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildMenu),
            name: .clipboardStoreDidChange, object: nil
        )

        hotkeyManager = GlobalHotkeyManager()
        hotkeyManager?.onHotkey = { [weak self] point in self?.showQuickMenuAtPoint(point) }
        hotkeyManager?.register()

        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor?.start()

        askLoginItemIfNeeded()
    }

    // MARK: - Login item

    private func askLoginItemIfNeeded() {
        let key = "didAskLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("login.prompt.title", comment: "")
            alert.informativeText = NSLocalizedString("login.prompt.message", comment: "")
            alert.addButton(withTitle: NSLocalizedString("login.prompt.enable", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("login.prompt.skip", comment: ""))
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                if #available(macOS 13.0, *) { try? SMAppService.mainApp.register() }
            }
        }
    }

    // MARK: - Quick menu

    func showQuickMenuAtPoint(_ mouseLocation: NSPoint) {
        previousFrontAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0

        let targetScreen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        let panel = QuickPickPanel(
            screen: targetScreen,
            onPaste: { [weak self] item in
                guard let self else { return }
                ClipboardStore.shared.copyToClipboard(item)
                self.pasteInApp(pid: self.previousFrontAppPID)
            },
            onCopy: { item in ClipboardStore.shared.copyToClipboard(item) }
        )
        panel.showCentered()
    }

    // MARK: - Menu construction

    @objc func rebuildMenu() { statusItem?.menu = buildMenu() }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let total = ClipboardStore.shared.items.count
        let countLabel = total == 1
            ? NSLocalizedString("menu.count.one", comment: "")
            : String(format: NSLocalizedString("menu.count.many", comment: ""), total)
        let countItem = NSMenuItem(title: countLabel, action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        countItem.attributedTitle = NSAttributedString(string: countLabel, attributes: attrs)
        menu.addItem(countItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: NSLocalizedString("menu.clear_all", comment: ""),
            action: #selector(clearAll), keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
        menu.addItem(clearItem)

        let settingsItem = NSMenuItem(
            title: NSLocalizedString("menu.settings", comment: ""),
            action: #selector(openShortcutSettings), keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: ""),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Clipboard menu item (tray)

    func makeClipboardMenuItem(_ item: ClipboardItem, pasteOnSelect: Bool = false) -> NSMenuItem {
        let menuItem = NSMenuItem()
        let rawTitle = item.previewText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        let isHexColor = Self.isHexColor(rawTitle)
        let isPassword = !isHexColor && SensitiveDataSettings.shared.isSensitive(rawTitle)
        let shouldMask = isPassword && !SensitiveDataSettings.shared.showSensitiveData

        var displayTitle = shouldMask
            ? String(repeating: "•", count: min(rawTitle.count, 16)) : rawTitle
        if displayTitle.count > 60 { displayTitle = String(displayTitle.prefix(57)) + "…" }
        if displayTitle.isEmpty { displayTitle = NSLocalizedString("item.empty", comment: "") }

        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        menuItem.attributedTitle = NSMutableAttributedString(string: displayTitle, attributes: attrs)
        menuItem.title = displayTitle
        menuItem.representedObject = item.id
        menuItem.target = self
        menuItem.action = pasteOnSelect
            ? #selector(selectAndPasteClipboardItem(_:)) : #selector(copyClipboardItem(_:))

        if isHexColor, let color = NSColor(hexString: rawTitle) {
            menuItem.image = Self.colorDotImage(color: color, size: 14)
        } else {
            let iconName: String
            switch item.content {
            case .text(let s):
                if isPassword { iconName = "lock.fill" }
                else if s.lowercased().hasPrefix("http") { iconName = "link" }
                else if s.contains("\n") { iconName = "text.alignleft" }
                else { iconName = "doc.text" }
            case .image: iconName = "photo"
            }
            menuItem.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            menuItem.image?.size = NSSize(width: 14, height: 14)
        }
        return menuItem
    }

    // MARK: - Content detection

    static func isHexColor(_ s: String) -> Bool {
        let pattern = #"^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    static func isURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: t),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else { return false }
        return true
    }

    static func colorDotImage(color: NSColor, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let path = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: size-2, height: size-2))
        color.setFill(); path.fill()
        NSColor.separatorColor.setStroke(); path.lineWidth = 0.5; path.stroke()
        img.unlockFocus()
        return img
    }

    // MARK: - Actions

    @objc func copyClipboardItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = ClipboardStore.shared.items.first(where: { $0.id == id }) else { return }
        ClipboardStore.shared.copyToClipboard(item)
    }

    @objc func selectAndPasteClipboardItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = ClipboardStore.shared.items.first(where: { $0.id == id }) else { return }
        let targetPID = previousFrontAppPID
        ClipboardStore.shared.copyToClipboard(item)
        pasteInApp(pid: targetPID)
    }

    var previousFrontAppPID: pid_t = 0

    private func pasteInApp(pid: pid_t) {
        guard pid != 0, let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard AXIsProcessTrusted() else { requestAccessibilityPermission(); return }
        app.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
            let vCode = UInt16(kVK_ANSI_V)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true)
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
            keyDown?.flags = .maskCommand; keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func clearAll() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.clear.title", comment: "")
        alert.informativeText = NSLocalizedString("alert.clear.message", comment: "")
        alert.addButton(withTitle: NSLocalizedString("alert.clear.confirm", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("alert.clear.cancel", comment: ""))
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { ClipboardStore.shared.clearAll() }
    }

    @objc func openShortcutSettings() {
        openAuxWindow(title: NSLocalizedString("shortcut.title", comment: ""),
                      size: NSSize(width: 420, height: 500),
                      window: &shortcutWindow) {
            ShortcutSettingsView(onSave: { [weak self] in
                self?.reRegisterHotkey()
            })
        }
    }

    func reRegisterHotkey() {
        hotkeyManager?.unregister()
        hotkeyManager?.register()
        rebuildMenu()
    }

    @objc func openTagManager() {
        openAuxWindow(title: "Gestione tag", size: NSSize(width: 360, height: 400),
                      window: &tagManagerWindow) { TagManagerView().environmentObject(ClipboardStore.shared) }
    }

    private func openAuxWindow<V: View>(title: String, size: NSSize,
                                        window: inout NSWindow?, @ViewBuilder content: () -> V) {
        if let existing = window { existing.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        win.title = title; win.center(); win.isReleasedWhenClosed = false
        win.contentViewController = NSHostingController(rootView: content())
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window = win
    }
}

// MARK: - Static helpers for QuickPickCell

extension AppDelegate {
    static func isHexColorStatic(_ s: String) -> Bool { isHexColor(s) }
    static func colorDotImageStatic(color: NSColor, size: CGFloat) -> NSImage { colorDotImage(color: color, size: size) }
    static func isURLStatic(_ s: String) -> Bool { isURL(s) }
}

// MARK: - QuickPickPanel

class QuickPickPanel: NSWindow, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    private let searchField = HotkeySearchField()
    private let tableView   = KeyPassTableView()
    private let scrollView  = NSScrollView()
    private let footerLabel = NSTextField(labelWithString: "")

    private var items: [ClipboardItem] = []
    private var query: String = ""
    private var debounceTimer: Timer?
    private var pendingPasteID: UUID? = nil
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var isCmdDown: Bool = false
    private let trashBtn = NSButton()

    var onPaste: ((ClipboardItem) -> Void)?
    var onCopy:  ((ClipboardItem) -> Void)?

    private static var currentPanel: QuickPickPanel?

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    private let baseHeight: CGFloat = 416
    private let panelWidth: CGFloat = 440

    init(screen: NSScreen, onPaste: @escaping (ClipboardItem) -> Void,
         onCopy: @escaping (ClipboardItem) -> Void) {
        let sf = screen.visibleFrame
        let origin = NSPoint(x: sf.midX - panelWidth/2, y: sf.midY - baseHeight/2)
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: panelWidth, height: baseHeight)),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        self.onPaste = onPaste; self.onCopy = onCopy
        level = .floating; isOpaque = false; backgroundColor = .clear
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false; hasShadow = true
        buildUI(); reload(query: "")
    }

    // MARK: - UI

    private func buildUI() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true

        let container = NSVisualEffectView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.material = .popover; container.blendingMode = .behindWindow
        container.state = .active; container.wantsLayer = true
        container.layer?.cornerRadius = 12; container.layer?.masksToBounds = true
        cv.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: cv.topAnchor),
            container.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = NSLocalizedString("panel.search.placeholder", comment: "")
        searchField.bezelStyle = .roundedBezel; searchField.focusRingType = .default
        searchField.font = NSFont.systemFont(ofSize: 14); searchField.delegate = self
        container.addSubview(searchField)

        trashBtn.translatesAutoresizingMaskIntoConstraints = false
        trashBtn.image = NSImage(systemSymbolName: "xmark.bin",
                                 accessibilityDescription: NSLocalizedString("accessibility.trash", comment: ""))
        trashBtn.bezelStyle = .regularSquare; trashBtn.isBordered = false
        trashBtn.contentTintColor = .secondaryLabelColor
        trashBtn.toolTip = NSLocalizedString("panel.trash.tooltip", comment: "")
        trashBtn.target = self; trashBtn.action = #selector(deleteLast10FromPanel)
        container.addSubview(trashBtn)

        let sep = NSBox()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.boxType = .separator; container.addSubview(sep)

        tableView.dataSource = self; tableView.delegate = self; tableView.headerView = nil
        tableView.rowHeight = 28; tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear; tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 2); tableView.focusRingType = .none
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        col.resizingMask = .autoresizingMask; tableView.addTableColumn(col)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView; scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = NSFont.systemFont(ofSize: 10)
        footerLabel.textColor = .tertiaryLabelColor; footerLabel.alignment = .center
        footerLabel.stringValue = NSLocalizedString("panel.footer", comment: "")
        container.addSubview(footerLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: trashBtn.leadingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 28),

            trashBtn.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            trashBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            trashBtn.widthAnchor.constraint(equalToConstant: 22),
            trashBtn.heightAnchor.constraint(equalToConstant: 22),

            sep.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -4),

            footerLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            footerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    // MARK: - Show / close

    func showCentered() {
        QuickPickPanel.currentPanel?.close()
        QuickPickPanel.currentPanel = self
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil); makeFirstResponder(searchField)

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isVisible else { return }; self.closePanel()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.window !== self { self.closePanel(); return nil }; return event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let cmdNow = event.modifierFlags.contains(.command)
            if cmdNow != self.isCmdDown {
                self.isCmdDown = cmdNow
                self.updateCellsForCmdState()
            }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive),
                                                name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func appDidResignActive() { closePanel() }

    func closePanel() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let k = keyMonitor   { NSEvent.removeMonitor(k); keyMonitor = nil }
        if let f = flagsMonitor { NSEvent.removeMonitor(f); flagsMonitor = nil }
        isCmdDown = false
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        ClipboardStore.shared.searchText = ""
        ClipboardStore.shared.matchCase  = false
        ClipboardStore.shared.matchWord  = false
        orderOut(nil); QuickPickPanel.currentPanel = nil
    }

    override func close() { closePanel(); super.close() }

    // MARK: - Data

    private func reload(query: String) {
        self.query = query
        setTrashVisible(query.isEmpty)
        ClipboardStore.shared.searchText = query

        let all = ClipboardStore.shared.items
        if query.isEmpty {
            items = Array(all.prefix(10))
        } else {
            let needle = ClipboardStore.shared.matchCase ? query : query.lowercased()
            let filtered = all.filter { item in
                guard case .text(let s) = item.content else { return false }
                let haystack = ClipboardStore.shared.matchCase ? s : s.lowercased()
                return haystack.contains(needle)
            }
            items = Array(filtered.prefix(10))
        }

        tableView.reloadData(); tableView.deselectAll(nil); pendingPasteID = nil
    }

    // MARK: - Row mapping

    private var totalRows: Int { items.count }

    private func rowContent(at row: Int) -> ClipboardItem { items[row] }

    // MARK: - TableView

    func numberOfRows(in tableView: NSTableView) -> Int { totalRows }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: cellID, owner: self) as? QuickPickCell)
            ?? QuickPickCell(identifier: cellID)
        cell.configure(item: rowContent(at: row), query: query,
                       matchCase: ClipboardStore.shared.matchCase, index: row)
        cell.updateLinkIcon(isCmdDown: isCmdDown, animated: false)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        QuickPickRowView()
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 30 }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    // MARK: - Search delegate

    func controlTextDidChange(_ obj: Notification) {
        let q = searchField.stringValue
        // Digit typed when field was empty → paste corresponding regular (non-pinned) item
        if query.isEmpty, q.count == 1, let ch = q.first, ch.isNumber {
            let digit = ch == "0" ? 9 : (Int(String(ch)) ?? 1) - 1
            if digit >= 0, digit < items.count {
                let item = items[digit]
                searchField.stringValue = ""; closePanel(); onPaste?(item); return
            }
        }
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.reload(query: q)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if searchField.stringValue.isEmpty { closePanel() }
            else { searchField.stringValue = ""; reload(query: "") }
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) { handleReturn(); return true }
        if selector == #selector(NSResponder.insertTab(_:)) {
            if totalRows > 0 { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
            makeFirstResponder(tableView); return true
        }
        if selector == #selector(NSResponder.moveUp(_:)) { moveSelection(by: -1); return true }
        if selector == #selector(NSResponder.moveDown(_:)) { moveSelection(by: 1); return true }
        return false
    }

    private func moveSelection(by delta: Int) {
        let count = totalRows; guard count > 0 else { return }
        let next = max(0, min(count-1, tableView.selectedRow + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next); pendingPasteID = nil
    }

    private func handleReturn() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard row < totalRows else { return }
        let item = rowContent(at: row)
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        if cmdHeld, case .text(let s) = item.content,
           AppDelegate.isURLStatic(s),
           let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            closePanel()
            NSWorkspace.shared.open(url)
            return
        }
        closePanel(); onPaste?(item)
    }

    private func flashRow(_ row: Int) {
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return }
        rowView.wantsLayer = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            rowView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15; rowView.layer?.backgroundColor = nil
            }
        }
    }

    private func updateCellsForCmdState() {
        for row in 0..<totalRows {
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? QuickPickCell {
                cell.updateLinkIcon(isCmdDown: isCmdDown)
            }
        }
    }

    // MARK: - Keyboard shortcuts

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if mods == .command {
                // CMD+D → delete last 10 recent items (only outside search mode)
                if event.keyCode == 2, query.isEmpty {
                    deleteLast10FromPanel(); return
                }
                // CMD+Return → open URL if selected item is a URL
                if event.keyCode == 36 {
                    let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
                    if row < totalRows,
                       case .text(let s) = rowContent(at: row).content,
                       AppDelegate.isURLStatic(s),
                       let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        closePanel(); NSWorkspace.shared.open(url); return
                    }
                }
                // CMD+digit → open URL at that index
                let chars = event.charactersIgnoringModifiers ?? ""
                if chars.count == 1, let ch = chars.first, ch.isNumber {
                    let digit = ch == "0" ? 9 : (Int(String(ch)) ?? 1) - 1
                    if digit >= 0, digit < items.count,
                       case .text(let s) = items[digit].content,
                       AppDelegate.isURLStatic(s),
                       let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        closePanel(); NSWorkspace.shared.open(url); return
                    }
                }
            }
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        let chars = event.characters ?? ""
        if event.keyCode == 36 { handleReturn(); return }

        // CMD + digit → open URL in browser (only for URL items)
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let charsIgnoring = event.charactersIgnoringModifiers ?? ""
        if mods == .command, charsIgnoring.count == 1, let ch = charsIgnoring.first, ch.isNumber {
            let digit = ch == "0" ? 9 : (Int(String(ch)) ?? 1) - 1
            if digit >= 0, digit < items.count {
                let item = items[digit]
                if case .text(let s) = item.content,
                   AppDelegate.isURLStatic(s),
                   let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    closePanel()
                    NSWorkspace.shared.open(url)
                    return
                }
            }
            super.keyDown(with: event); return
        }

        guard chars.count == 1, let ch = chars.first, ch.isNumber,
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            super.keyDown(with: event); return
        }
        // Digit shortcuts apply to regular (non-pinned) items
        let digit = ch == "0" ? 9 : (Int(String(ch)) ?? 1) - 1
        guard digit >= 0, digit < items.count else { super.keyDown(with: event); return }
        let item = items[digit]; closePanel(); onPaste?(item)
    }

    private func setTrashVisible(_ visible: Bool) {
        if visible {
            trashBtn.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                trashBtn.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                trashBtn.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.trashBtn.alphaValue == 0 else { return }
                self.trashBtn.isHidden = true
            })
        }
    }

    @objc private func deleteLast10FromPanel() {
        for item in items {
            ClipboardStore.shared.delete(item)
        }
        reload(query: query)
    }
}

// MARK: - KeyPassTableView

class KeyPassTableView: NSTableView {
    override func keyDown(with event: NSEvent) {
        let chars = event.characters ?? ""
        if event.keyCode == 36 { window?.keyDown(with: event); return }
        if chars.count == 1, let ch = chars.first, ch.isNumber {
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            if mods.isEmpty || mods == .command { window?.keyDown(with: event); return }
        }
        if event.keyCode == 53 { window?.keyDown(with: event); return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { super.mouseDown(with: event); return }
        // Let the panel decide if row is selectable (separator rows are not)
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if let returnEvent = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ) { window?.keyDown(with: returnEvent) }
    }
}

// MARK: - QuickPickCell

class QuickPickCell: NSTableCellView {
    private let numLabel    = NSTextField(labelWithString: "")
    private let iconView    = NSImageView()
    private let textLabel   = NSTextField(labelWithString: "")
    private let linkIconView = NSImageView()
    private var isURLItem   = false

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero); self.identifier = identifier

        numLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        numLabel.textColor = .tertiaryLabelColor
        numLabel.translatesAutoresizingMaskIntoConstraints = false; numLabel.alignment = .right
        addSubview(numLabel)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        textLabel.font = NSFont.systemFont(ofSize: 13)
        textLabel.lineBreakMode = .byTruncatingTail; textLabel.maximumNumberOfLines = 1
        textLabel.cell?.wraps = false; textLabel.cell?.isScrollable = true
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        linkIconView.translatesAutoresizingMaskIntoConstraints = false
        linkIconView.imageScaling = .scaleProportionallyDown
        linkIconView.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        linkIconView.contentTintColor = .controlAccentColor
        linkIconView.alphaValue = 0
        addSubview(linkIconView)

        NSLayoutConstraint.activate([
            numLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            numLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            numLabel.widthAnchor.constraint(equalToConstant: 16),

            iconView.leadingAnchor.constraint(equalTo: numLabel.trailingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            textLabel.trailingAnchor.constraint(equalTo: linkIconView.leadingAnchor, constant: -4),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            linkIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            linkIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            linkIconView.widthAnchor.constraint(equalToConstant: 14),
            linkIconView.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(item: ClipboardItem, query: String, matchCase: Bool, index: Int) {
        numLabel.stringValue = index < 9 ? "\(index+1)" : (index == 9 ? "0" : "")

        let rawText: String
        switch item.content { case .text(let s): rawText = s; case .image: rawText = "" }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHexColor = AppDelegate.isHexColorStatic(trimmed)
        let isPassword = !isHexColor && SensitiveDataSettings.shared.isSensitive(trimmed)
        let shouldMask = isPassword && !SensitiveDataSettings.shared.showSensitiveData
        isURLItem = !isPassword && AppDelegate.isURLStatic(trimmed)
        linkIconView.alphaValue = 0

        var display = shouldMask
            ? String(repeating: "•", count: min(rawText.count, 20))
            : rawText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        if display.count > 55 { display = String(display.prefix(52)) + "…" }
        if display.isEmpty { display = NSLocalizedString("item.empty", comment: "") }

        if isHexColor, let color = NSColor(hexString: trimmed) {
            iconView.image = AppDelegate.colorDotImageStatic(color: color, size: 13)
        } else {
            let iconName: String
            switch item.content {
            case .text(let s):
                if isPassword { iconName = "lock.fill" }
                else if s.lowercased().hasPrefix("http") { iconName = "link" }
                else if s.contains("\n") { iconName = "text.alignleft" }
                else { iconName = "doc.text" }
            case .image: iconName = "photo"
            }
            let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            img?.size = NSSize(width: 13, height: 13); iconView.image = img
        }

        if !query.isEmpty && !shouldMask {
            textLabel.attributedStringValue = highlightedString(display, query: query, matchCase: matchCase)
        } else {
            textLabel.stringValue = display; textLabel.textColor = .labelColor
        }
    }

    func updateLinkIcon(isCmdDown: Bool, animated: Bool = true) {
        let target: CGFloat = (isCmdDown && isURLItem) ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                linkIconView.animator().alphaValue = target
            }
        } else {
            linkIconView.alphaValue = target
        }
    }

    private func highlightedString(_ text: String, query: String, matchCase: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
        ])
        let options: String.CompareOptions = matchCase ? [] : .caseInsensitive
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: options, range: searchRange) {
            // controlAccentColor con alpha bassa per il background del match —
            // funziona con qualsiasi colore accento, dal blu all'arancione al rosso
            result.addAttributes([
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.2),
                .foregroundColor: NSColor.controlAccentColor
            ], range: NSRange(range, in: text))
            searchRange = range.upperBound..<text.endIndex
        }
        return result
    }
}

// MARK: - QuickPickRowView

class QuickPickRowView: NSTableRowView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    private var panel: QuickPickPanel? { window as? QuickPickPanel }

    override func mouseEntered(with event: NSEvent) {
        if let tv = superview as? NSTableView {
            let row = tv.row(for: self)
            if row >= 0 {
                tv.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        needsDisplay = true
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // selectedContentBackgroundColor è il colore semantico macOS per le selezioni —
        // rispetta automaticamente l'accento utente con il contrasto corretto.
        // Quando la window non è key usiamo unemphasizedSelectedContentBackgroundColor.
        let color: NSColor = window?.isKeyWindow == true
            ? .selectedContentBackgroundColor
            : .unemphasizedSelectedContentBackgroundColor
        color.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
    override var isEmphasized: Bool { get { true } set {} }
}

// MARK: - HotkeySearchField

class HotkeySearchField: NSSearchField {}

// MARK: - Notification

extension Notification.Name {
    static let clipboardStoreDidChange = Notification.Name("clipboardStoreDidChange")
}

// MARK: - ShortcutSettingsView

struct ShortcutSettingsView: View {
    var onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // App icon + name + version header
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("Tweezy")
                        .font(.system(size: 18, weight: .bold))
                    Text("\(NSLocalizedString("settings.version", comment: "")) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Shortcuts section
                SettingsSectionCard(title: NSLocalizedString("settings.shortcuts", comment: "")) {
                    ShortcutCardRow(
                        label: NSLocalizedString("shortcut.open_panel", comment: ""),
                        keyCode: GlobalHotkeyManager.savedKeyCode,
                        modifiers: GlobalHotkeyManager.savedModifiers,
                        defaultKeyCode: GlobalHotkeyManager.defaultKeyCode,
                        defaultModifiers: GlobalHotkeyManager.defaultModifiers,
                        onSave: onSave
                    )
                }

                Spacer(minLength: 20)

                // Sensitive data section
                SettingsSectionCard(title: NSLocalizedString("settings.sensitive", comment: "")) {
                    SensitiveSettingsSection()
                }

                Spacer(minLength: 20)
            }
        }
        .frame(width: 420, height: 500)
    }
}

// MARK: - SensitiveSettingsSection

struct SensitiveSettingsSection: View {
    @ObservedObject private var settings = SensitiveDataSettings.shared
    @State private var draftPattern = SensitiveDataSettings.shared.pattern

    private var isPatternValid: Bool {
        (try? NSRegularExpression(pattern: draftPattern)) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(NSLocalizedString("settings.sensitive.pattern", comment: ""))
                        .font(.system(size: 13))
                    Spacer()
                    if !draftPattern.isEmpty && !isPatternValid {
                        Label(NSLocalizedString("settings.sensitive.invalid", comment: ""),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                TextField("", text: $draftPattern)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draftPattern) { newValue in
                        if (try? NSRegularExpression(pattern: newValue)) != nil {
                            settings.pattern = newValue
                        }
                    }
                HStack {
                    Spacer()
                    Button(NSLocalizedString("settings.sensitive.reset", comment: "")) {
                        draftPattern = SensitiveDataSettings.defaultPattern
                        settings.pattern = SensitiveDataSettings.defaultPattern
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("settings.sensitive.show", comment: ""))
                        .font(.system(size: 13))
                    Text(NSLocalizedString("settings.sensitive.show.hint", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.showSensitiveData)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - SettingsSectionCard

struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - ShortcutCardRow

struct ShortcutCardRow: View {
    let label: String
    let defaultKeyCode: UInt32
    let defaultModifiers: UInt32
    var onSave: () -> Void

    @State private var currentKeyCode: UInt32
    @State private var currentModifiers: UInt32
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    init(label: String, keyCode: UInt32, modifiers: UInt32,
         defaultKeyCode: UInt32, defaultModifiers: UInt32, onSave: @escaping () -> Void) {
        self.label = label
        self.defaultKeyCode = defaultKeyCode
        self.defaultModifiers = defaultModifiers
        self.onSave = onSave
        _currentKeyCode = State(initialValue: keyCode)
        _currentModifiers = State(initialValue: modifiers)
    }

    private var displayString: String {
        GlobalHotkeyManager.displayString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if isRecording {
                    Text(NSLocalizedString("shortcut.hint", comment: ""))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            Spacer()

            Text(displayString)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording
                              ? Color.accentColor.opacity(0.12)
                              : Color(nsColor: .separatorColor).opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )

            Button(isRecording
                   ? NSLocalizedString("shortcut.stop", comment: "")
                   : NSLocalizedString("shortcut.record", comment: "")) {
                if isRecording { stopRecording() } else { startRecording() }
            }
            .controlSize(.small)

            Button(NSLocalizedString("shortcut.reset", comment: "")) {
                stopRecording()
                currentKeyCode = defaultKeyCode
                currentModifiers = defaultModifiers
                saveAndNotify()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbonMods = GlobalHotkeyManager.carbonModifiers(from: flags)
            guard carbonMods != 0 else { return nil }

            var modCount = 0
            if flags.contains(.command) { modCount += 1 }
            if flags.contains(.shift)   { modCount += 1 }
            if flags.contains(.option)  { modCount += 1 }
            if flags.contains(.control) { modCount += 1 }
            guard (modCount + 1) >= 2, (modCount + 1) <= 4 else { return nil }

            currentKeyCode = UInt32(event.keyCode)
            currentModifiers = carbonMods
            stopRecording()
            saveAndNotify()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func saveAndNotify() {
        GlobalHotkeyManager.save(keyCode: currentKeyCode, modifiers: currentModifiers)
        onSave()
    }
}

// MARK: - TagManagerView

struct TagManagerView: View {
    @EnvironmentObject var store: ClipboardStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack { Text("Tag Manager").padding() }
            .frame(width: 360, height: 400)
    }
}

// MARK: - NSColor hex extension

extension NSColor {
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >>  8) & 0xFF) / 255
            a = CGFloat( value        & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >>  8) & 0xFF) / 255
            b = CGFloat( value        & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
