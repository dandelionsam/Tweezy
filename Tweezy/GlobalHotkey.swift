import AppKit
import Carbon.HIToolbox

class GlobalHotkeyManager {
    var onHotkey: ((NSPoint) -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var selfPtr: UnsafeMutableRawPointer?

    func register() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CLPM"), id: 1)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32   = UInt32(kVK_ANSI_V)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<GlobalHotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                mgr.hotkeyPressed()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let r = hotKeyRef   { UnregisterEventHotKey(r); hotKeyRef = nil }
        if let r = eventHandlerRef { RemoveEventHandler(r); eventHandlerRef = nil }
    }

    private func hotkeyPressed() {
        DispatchQueue.main.async { [weak self] in
            self?.onHotkey?(NSEvent.mouseLocation)
        }
    }

    private func fourCharCode(_ s: String) -> OSType {
        assert(s.count == 4)
        return s.unicodeScalars.reduce(0) { ($0 << 8) + OSType($1.value) }
    }
}
