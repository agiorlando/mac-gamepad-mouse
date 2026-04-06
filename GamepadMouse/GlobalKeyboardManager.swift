import AppKit
import ApplicationServices
import GameController
import SwiftUI

// MARK: - AX: detect keyboard-capable focus (any app)

enum AXFocusInspector {

    /// Accessibility role string of the focused UI element, if readable.
    static func focusedElementRole() -> String? {
        guard AccessibilityGate.isTrusted else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let ref = focused else { return nil }
        let element = ref as! AXUIElement
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let r = role as? String else { return nil }
        return r
    }

    /// Roles that typically accept typing (Chrome omnibox is often `AXTextField` or `AXComboBox`).
    static func roleAcceptsKeyboardInput(_ role: String) -> Bool {
        if role == "AXSecureTextField" { return false }
        let ok: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        return ok.contains(role)
    }
}

// MARK: - Floating panel (does not steal key from Chrome, etc.)

final class NonActivatingKeyboardPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        title = "Gamepad Keyboard"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class KeyboardPanelCloseForwarder: NSObject, NSWindowDelegate {
    weak var owner: GlobalKeyboardManager?

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            owner?.hidePanel()
        }
    }
}

// MARK: - Coordinator

@MainActor
final class GlobalKeyboardManager: ObservableObject {

    @Published var isPanelVisible = false
    @Published var autoShowOnTextFocus = true

    let keyboardInjector: KeyboardInjector

    private let controllerService: ControllerService
    private let gamepadUIState: GamepadUIState

    private var panelWindow: NonActivatingKeyboardPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var panelCloseForwarder: KeyboardPanelCloseForwarder?
    private var auxTimer: Timer?

    private var l3WasDown = false
    private var focusPollCounter = 0
    private var lastSawTextCapableFocus = false
    /// If true, leaving a text field will auto-hide. L3-opened panels keep this false.
    private var hideWhenFocusLeavesTextField = false
    /// After the user closes the panel while still in a text field, don’t auto-open again until focus leaves text-capable UI (avoids reopen loop).
    private var suppressAutoReopenUntilTextBlur = false

    init(controllerService: ControllerService, gamepadUIState: GamepadUIState, keyboardInjector: KeyboardInjector) {
        self.controllerService = controllerService
        self.gamepadUIState = gamepadUIState
        self.keyboardInjector = keyboardInjector
        startAuxiliaryPolling()
    }

    /// Call once from `GamepadMouseApp` so when mouse control is on we share one 60 Hz timer instead of also running a 30 Hz aux timer.
    func attachMergedPolling(for inputEngine: InputEngine) {
        inputEngine.mergePollCoordinator = self
    }

    deinit {
        auxTimer?.invalidate()
    }

    func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel(autoTriggered: false)
        }
    }

    func showPanel(autoTriggered: Bool) {
        if !autoTriggered {
            suppressAutoReopenUntilTextBlur = false
        }
        hideWhenFocusLeavesTextField = autoTriggered
        ensurePanel()
        isPanelVisible = true
        gamepadUIState.onScreenKeyboardVisible = true
        panelWindow?.orderFrontRegardless()
    }

    /// - Parameter userInitiated: `true` for L3, Close, or window close. `false` when the panel is hidden because focus left a text field (auto-dismiss).
    func hidePanel(userInitiated: Bool = true) {
        hideWhenFocusLeavesTextField = false
        if userInitiated {
            suppressAutoReopenUntilTextBlur = true
        }
        panelWindow?.orderOut(nil)
        isPanelVisible = false
        gamepadUIState.onScreenKeyboardVisible = false
    }

    private func hideIfAutoDismissEligible() {
        guard hideWhenFocusLeavesTextField else { return }
        hidePanel(userInitiated: false)
    }

    private func ensurePanel() {
        guard panelWindow == nil else { return }
        let rect = NSRect(x: 0, y: 0, width: 600, height: 480)
        let window = NonActivatingKeyboardPanel(contentRect: rect)
        let forwarder = KeyboardPanelCloseForwarder()
        forwarder.owner = self
        window.delegate = forwarder
        panelCloseForwarder = forwarder
        let root = AnyView(
            GamepadKeyboardPanelContent(manager: self)
                .environmentObject(controllerService)
                .environmentObject(gamepadUIState)
        )
        let host = NSHostingController(rootView: root)
        window.contentViewController = host
        window.center()
        panelWindow = window
        hostingController = host
    }

    private func startAuxiliaryPolling() {
        auxTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.auxTick()
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        auxTimer = t
    }

    /// Stops the 30 Hz timer while `InputEngine` owns a 60 Hz timer (same main-thread work, half as many wakeups).
    func inputEngineMainTimerStarted() {
        auxTimer?.invalidate()
        auxTimer = nil
    }

    /// Restarts aux polling when mouse control turns off (L3 + auto-show still needed).
    func inputEngineMainTimerStopped() {
        startAuxiliaryPolling()
    }

    /// Folded into `InputEngine`’s 60 Hz tick: L3 every frame, Accessibility focus poll ~5 Hz (every 12 frames).
    func onInputEngineTimerTick(frameIndex: Int, extendedGamepad: GCExtendedGamepad?) {
        guard AccessibilityGate.isTrusted else { return }

        if let pad = extendedGamepad {
            let l3 = pad.leftThumbstickButton?.isPressed == true
            if l3 && !l3WasDown {
                togglePanel()
            }
            l3WasDown = l3
        }

        guard autoShowOnTextFocus else { return }
        guard frameIndex % 12 == 0 else { return }
        performAutoShowFocusPoll()
    }

    // `InputEngine`’s `Timer` fires on the main run loop but is not MainActor-isolated; hop into the actor without async latency.
    nonisolated func inputEngineMainTimerStartedFromMainRunLoop() {
        MainActor.assumeIsolated {
            self.inputEngineMainTimerStarted()
        }
    }

    nonisolated func inputEngineMainTimerStoppedFromMainRunLoop() {
        MainActor.assumeIsolated {
            self.inputEngineMainTimerStopped()
        }
    }

    nonisolated func onInputEngineTimerTickFromMainRunLoop(frameIndex: Int, extendedGamepad: GCExtendedGamepad?) {
        MainActor.assumeIsolated {
            self.onInputEngineTimerTick(frameIndex: frameIndex, extendedGamepad: extendedGamepad)
        }
    }

    private func auxTick() {
        guard AccessibilityGate.isTrusted else { return }

        if let pad = controllerService.selectedController?.extendedGamepad {
            let l3 = pad.leftThumbstickButton?.isPressed == true
            if l3 && !l3WasDown {
                togglePanel()
            }
            l3WasDown = l3
        }

        guard autoShowOnTextFocus else { return }

        focusPollCounter += 1
        guard focusPollCounter >= 6 else { return }
        focusPollCounter = 0

        performAutoShowFocusPoll()
    }

    private func performAutoShowFocusPoll() {
        guard let role = AXFocusInspector.focusedElementRole() else {
            suppressAutoReopenUntilTextBlur = false
            if lastSawTextCapableFocus {
                hideIfAutoDismissEligible()
            }
            lastSawTextCapableFocus = false
            return
        }

        let texty = AXFocusInspector.roleAcceptsKeyboardInput(role)
        if texty {
            lastSawTextCapableFocus = true
            if !isPanelVisible, !suppressAutoReopenUntilTextBlur {
                showPanel(autoTriggered: true)
            }
        } else {
            suppressAutoReopenUntilTextBlur = false
            if lastSawTextCapableFocus {
                hideIfAutoDismissEligible()
            }
            lastSawTextCapableFocus = false
        }
    }
}

// MARK: - SwiftUI content hosted in panel

struct GamepadKeyboardPanelContent: View {
    @ObservedObject var manager: GlobalKeyboardManager
    @EnvironmentObject private var controllerService: ControllerService
    @EnvironmentObject private var gamepadUIState: GamepadUIState
    @StateObject private var vm = OnScreenKeyboardViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Text("Gamepad keyboard")
                .font(.headline)
            Text("Characters are sent to the app that has keyboard focus (e.g. Chrome’s address bar).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !vm.echoedTail.isEmpty {
                Text(vm.echoedTail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }

            HStack {
                Label(vm.capsLock ? "CAPS" : "caps", systemImage: "capslock.fill")
                    .foregroundStyle(vm.capsLock ? .primary : .secondary)
                    .font(.caption)
                Label(vm.shiftSticky ? "SHIFT" : "shift", systemImage: "shift.fill")
                    .foregroundStyle(vm.shiftSticky ? .primary : .secondary)
                    .font(.caption)
                Spacer()
                Text(vm.layerKind == .letters ? "ABC" : (vm.layerKind == .numbers ? "123" : "#+="))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(Array(vm.rows.enumerated()), id: \.offset) { ri, row in
                    HStack(spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { ci, key in
                            let selected = ri == vm.selectionRow && ci == vm.selectionCol
                            Text(key.label)
                                .font(.system(size: key.label.count > 2 ? 11 : 14, weight: selected ? .bold : .regular))
                                .frame(minWidth: 28, minHeight: 32)
                                .padding(.horizontal, 6)
                                .background(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(10)

            Text(vm.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Close") {
                manager.hidePanel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 400)
        .onAppear {
            vm.onDismiss = { manager.hidePanel() }
            vm.start(
                controllerService: controllerService,
                keyboardInjector: manager.keyboardInjector
            )
            gamepadUIState.onScreenKeyboardVisible = true
        }
        .onDisappear {
            vm.stop()
            gamepadUIState.onScreenKeyboardVisible = false
        }
    }
}
