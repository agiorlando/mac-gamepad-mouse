import AppKit
import SwiftUI

/// Ensures the app participates like a normal document-style app (Dock, ⌘Tab, Mission Control, Launchpad when installed in Applications).
private final class GamepadMouseAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            Self.configureMainWindows()
        }
    }

    private static func configureMainWindows() {
        for window in NSApp.windows {
            guard !(window is NSPanel) else { continue }
            var behavior = window.collectionBehavior
            behavior.remove(.stationary)
            behavior.insert(.managed)
            window.collectionBehavior = behavior
            window.isExcludedFromWindowsMenu = false
            if window.title.isEmpty {
                window.title = "Gamepad Mouse"
            }
        }
    }
}

/// Hooks the SwiftUI host window once it exists (may appear after `applicationDidFinishLaunching`).
private struct MainSwiftUIWindowHook: NSViewRepresentable {
    final class Coordinator {
        var didApply = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.didApply else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window, !(window is NSPanel) else { return }
            context.coordinator.didApply = true
            NSApp.setActivationPolicy(.regular)
            var behavior = window.collectionBehavior
            behavior.remove(.stationary)
            behavior.insert(.managed)
            window.collectionBehavior = behavior
            window.isExcludedFromWindowsMenu = false
            window.title = "Gamepad Mouse"
        }
    }
}

@main
struct GamepadMouseApp: App {
    @NSApplicationDelegateAdaptor(GamepadMouseAppDelegate.self) private var appDelegate
    @StateObject private var controllerService: ControllerService
    @StateObject private var gamepadUIState: GamepadUIState
    @StateObject private var keyboardManager: GlobalKeyboardManager
    @StateObject private var inputEngine: InputEngine

    init() {
        let cs = ControllerService()
        let ui = GamepadUIState()
        let mouse = MouseInjector()
        let keys = KeyboardInjector()
        let km = GlobalKeyboardManager(controllerService: cs, gamepadUIState: ui, keyboardInjector: keys)
        let ie = InputEngine(controllerService: cs, mouse: mouse, keyboard: keys, uiState: ui)
        km.attachMergedPolling(for: ie)
        _controllerService = StateObject(wrappedValue: cs)
        _gamepadUIState = StateObject(wrappedValue: ui)
        _keyboardManager = StateObject(wrappedValue: km)
        _inputEngine = StateObject(wrappedValue: ie)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controllerService)
                .environmentObject(inputEngine)
                .environmentObject(gamepadUIState)
                .environmentObject(keyboardManager)
                .background(MainSwiftUIWindowHook())
        }
    }
}
