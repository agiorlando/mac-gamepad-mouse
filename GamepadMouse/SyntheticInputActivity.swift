import Foundation

/// Prevents App Nap from throttling the main RunLoop while we poll the gamepad and post synthetic events.
/// Without this, mouse/keyboard injection often stops when another app is focused.
enum SyntheticInputActivity {

    private static var token: NSObjectProtocol?

    static func setActive(_ active: Bool) {
        if active {
            guard token == nil else { return }
            token = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated,
                reason: "Gamepad Mouse reads the controller and posts pointer/keyboard events."
            )
        } else if let t = token {
            ProcessInfo.processInfo.endActivity(t)
            token = nil
        }
    }
}
