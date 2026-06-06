import AppKit
import Foundation

class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if ClipboardStore.shared.skipNextClipboardChange {
            ClipboardStore.shared.skipNextClipboardChange = false; return
        }
        let frontRunningApp = NSWorkspace.shared.frontmostApplication
        if let bundleID = frontRunningApp?.bundleIdentifier,
           ExcludedAppsSettings.shared.isExcluded(bundleID) { return }
        let frontAppName = frontRunningApp?.localizedName
        if let string = pb.string(forType: .string), !string.isEmpty {
            let item = ClipboardItem(content: .text(string), appName: frontAppName)
            DispatchQueue.main.async { ClipboardStore.shared.add(item) }
            return
        }
        if let imageData = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            let item = ClipboardItem(content: .image(imageData), appName: frontAppName)
            DispatchQueue.main.async { ClipboardStore.shared.add(item) }
        }
    }
}
