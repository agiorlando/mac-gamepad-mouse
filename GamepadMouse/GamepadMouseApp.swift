import SwiftUI

@main
struct GamepadMouseApp: App {
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
        }
    }
}
