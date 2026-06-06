import AppKit
import Carbon.HIToolbox

class GlobalHotkeyManager {
    var onHotkey: ((NSPoint) -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var selfPtr: UnsafeMutableRawPointer?

    // MARK: - UserDefaults keys & defaults

    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    private static let udKeyCode   = "hotkeyKeyCode"
    private static let udModifiers = "hotkeyModifiers"

    static var savedKeyCode: UInt32 {
        let v = UserDefaults.standard.integer(forKey: udKeyCode)
        return v == 0 ? defaultKeyCode : UInt32(v)
    }

    static var savedModifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: udModifiers)
        if stored == nil { return defaultModifiers }
        return UInt32(UserDefaults.standard.integer(forKey: udModifiers))
    }

    static func save(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: udKeyCode)
        UserDefaults.standard.set(Int(modifiers), forKey: udModifiers)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: udKeyCode)
        UserDefaults.standard.removeObject(forKey: udModifiers)
    }

    // MARK: - Register / unregister

    func register() {
        register(keyCode: Self.savedKeyCode, modifiers: Self.savedModifiers)
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        let hotKeyID = EventHotKeyID(signature: fourCharCode("CLPM"), id: 1)
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

    // MARK: - Display string

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { parts += "⌘" }
        parts += keyName(for: keyCode)
        return parts
    }

    static func currentDisplayString() -> String {
        displayString(keyCode: savedKeyCode, modifiers: savedModifiers)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "PgUp", UInt32(kVK_PageDown): "PgDn",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_ANSI_Grave): "`",
        ]
        return map[keyCode] ?? "?"
    }

    /// Convert NSEvent modifier flags to Carbon modifier mask
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    /// Convert Carbon modifier mask to NSEvent modifier flags
    static func nsModifiers(from carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonMods & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        if carbonMods & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if carbonMods & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if carbonMods & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }
}

// MARK: - DeleteShortcutManager

enum DeleteShortcutManager {
    static let defaultKeyCode: UInt32   = UInt32(kVK_Delete)
    static let defaultModifiers: UInt32 = UInt32(cmdKey)

    private static let udKeyCode   = "deleteShortcutKeyCode"
    private static let udModifiers = "deleteShortcutModifiers"

    static var savedKeyCode: UInt32 {
        let v = UserDefaults.standard.integer(forKey: udKeyCode)
        return v == 0 ? defaultKeyCode : UInt32(v)
    }

    static var savedModifiers: UInt32 {
        guard UserDefaults.standard.object(forKey: udModifiers) != nil else { return defaultModifiers }
        return UInt32(UserDefaults.standard.integer(forKey: udModifiers))
    }

    static func save(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: udKeyCode)
        UserDefaults.standard.set(Int(modifiers), forKey: udModifiers)
    }
}
