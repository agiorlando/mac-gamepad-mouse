import ApplicationServices
import AppKit

enum AccessibilityGate {

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user once if not trusted (shows system dialog).
    static func promptIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
