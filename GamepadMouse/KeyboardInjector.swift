import Carbon
import CoreGraphics

/// Posts synthetic arrow-key taps for D-pad → text navigation in any focused field.
final class KeyboardInjector {

    private let source = CGEventSource(stateID: .hidSystemState)

    enum Arrow {
        case left, right, up, down

        fileprivate var keyCode: CGKeyCode {
            switch self {
            case .left: return CGKeyCode(kVK_LeftArrow)
            case .right: return CGKeyCode(kVK_RightArrow)
            case .up: return CGKeyCode(kVK_UpArrow)
            case .down: return CGKeyCode(kVK_DownArrow)
            }
        }
    }

    /// One key-down / key-up pair (character-producing apps see a single arrow step).
    func tapArrow(_ arrow: Arrow) {
        postKey(keyCode: arrow.keyCode, keyDown: true)
        postKey(keyCode: arrow.keyCode, keyDown: false)
    }

    /// Sends text as HID Unicode key events (one `Character` at a time for compatibility).
    func typeText(_ text: String) {
        for ch in text {
            typeTextChunk(String(ch))
        }
    }

    private func typeTextChunk(_ text: String) {
        var utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }
        utf16.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            down.post(tap: CGEventTapLocation.cghidEventTap)
            guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
            up.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    /// Laptop “delete” / backward delete (left of forward-delete on full keyboard).
    func tapBackwardDelete() {
        tapKeyCode(CGKeyCode(kVK_Delete))
    }

    func tapReturnKey() {
        tapKeyCode(CGKeyCode(kVK_Return))
    }

    private func tapKeyCode(_ code: CGKeyCode) {
        postKey(keyCode: code, keyDown: true)
        postKey(keyCode: code, keyDown: false)
    }

    private func postKey(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
