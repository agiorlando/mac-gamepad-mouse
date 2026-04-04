import Combine
import Foundation

/// Shared UI flags so gamepad routing can avoid conflicts (e.g. OSK uses D-pad + face buttons).
final class GamepadUIState: ObservableObject {
    @Published var onScreenKeyboardVisible = false
}
