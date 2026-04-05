import GameController
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controllerService: ControllerService
    @EnvironmentObject private var inputEngine: InputEngine
    @EnvironmentObject private var gamepadUIState: GamepadUIState
    @EnvironmentObject private var keyboardManager: GlobalKeyboardManager
    @State private var accessibilityTrusted = AccessibilityGate.isTrusted

    private let trustPoll = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            mainTab
                .tabItem { Label("Control", systemImage: "gamecontroller") }
            TestSurfaceView()
                .tabItem { Label("Test", systemImage: "cursorarrow.click") }
        }
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            controllerService.refreshControllers()
            controllerService.startWirelessDiscovery()
            syncSyntheticInputActivity()
        }
        .onDisappear {
            inputEngine.stopTimer()
            SyntheticInputActivity.setActive(false)
        }
        .onReceive(trustPoll) { _ in
            let trusted = AccessibilityGate.isTrusted
            if trusted != accessibilityTrusted {
                accessibilityTrusted = trusted
            }
        }
        .onChange(of: accessibilityTrusted) { trusted in
            inputEngine.updateAccessibilityTrustState()
            if trusted {
                inputEngine.onEnabledChanged()
            } else {
                inputEngine.isEnabled = false
                inputEngine.stopTimer()
            }
            syncSyntheticInputActivity()
        }
        .onChange(of: inputEngine.isEnabled) { _ in
            inputEngine.onEnabledChanged()
            syncSyntheticInputActivity()
        }
        .onChange(of: gamepadUIState.onScreenKeyboardVisible) { _ in
            syncSyntheticInputActivity()
        }
        .onChange(of: keyboardManager.isPanelVisible) { _ in
            syncSyntheticInputActivity()
        }
    }

    /// Keeps polling alive when another app is focused (mitigates App Nap timer throttling).
    private func syncSyntheticInputActivity() {
        let needMouse = inputEngine.isEnabled && accessibilityTrusted
        let needKeyboard = gamepadUIState.onScreenKeyboardVisible
        SyntheticInputActivity.setActive(needMouse || needKeyboard)
    }

    private var mainTab: some View {
        Form {
            Section {
                if accessibilityTrusted {
                    Label("Accessibility is enabled for Gamepad Mouse.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allow this app to control your Mac")
                            .font(.headline)
                        Text(
                            "Gamepad Mouse needs Accessibility permission to move the pointer and send clicks."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Text(
                            "If you just rebuilt in Xcode: each new debug build is signed differently, so macOS treats it as a new app. "
                                + "Open Accessibility below, remove every “Gamepad Mouse” entry (use −), then run this build again and turn the new entry on."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Text(
                            "Signing with your Apple Development team in Xcode reduces how often this happens; ad hoc “Sign to Run Locally” resets trust whenever the binary changes."
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        HStack {
                            Button("Open Accessibility Settings") {
                                AccessibilityGate.openAccessibilitySettings()
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Prompt Again") {
                                AccessibilityGate.promptIfNeeded()
                            }
                        }
                    }
                }
            } header: {
                Text("Permission")
            }

            Section {
                Picker("Controller", selection: $controllerService.selectedObjectID) {
                    Text("None").tag(Optional<ObjectIdentifier>.none)
                    ForEach(controllerService.controllers) { c in
                        Text(controllerService.displayName(for: c))
                            .tag(Optional(ObjectIdentifier(c)))
                    }
                }
                .disabled(controllerService.controllers.isEmpty)

                if controllerService.isDiscoveringWireless {
                    Label("Searching for wireless controllers…", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Search for wireless controllers") {
                    controllerService.startWirelessDiscovery()
                }
                .disabled(controllerService.isDiscoveringWireless)
            } header: {
                Text("Gamepad")
            }

            Section {
                Toggle("Auto-show keyboard when a text field is focused (any app)", isOn: $keyboardManager.autoShowOnTextFocus)
                    .disabled(!accessibilityTrusted)
                Text(
                    "Press L3 (click the left stick) to show or hide the floating keyboard anytime — a common controller convention."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Virtual keyboard")
            } footer: {
                Text(
                    "Reads the focused control via Accessibility (same permission as mouse). Secure password fields are skipped. "
                        + "Typed characters are sent as real key events to the frontmost app (Chrome, Safari, etc.)."
                )
            }

            Section {
                Toggle("Enable mouse control", isOn: $inputEngine.isEnabled)
                    .disabled(!accessibilityTrusted)

                VStack(alignment: .leading) {
                    Text("Pointer sensitivity: \(Int(inputEngine.pointerSensitivity)) pt/s")
                    Slider(value: $inputEngine.pointerSensitivity, in: 200...4000, step: 50)
                }

                VStack(alignment: .leading) {
                    Text("Scroll speed: \(Int(inputEngine.scrollSpeed))")
                    Slider(value: $inputEngine.scrollSpeed, in: 5...120, step: 1)
                }

                VStack(alignment: .leading) {
                    Text("Stick deadzone: \(Int(inputEngine.deadzone * 100))%")
                    Slider(value: $inputEngine.deadzone, in: 0.05...0.35, step: 0.01)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Last input tick")
                    Spacer()
                    Text(inputEngine.lastTickSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Mapping")
            } footer: {
                Text(
                    "Left stick moves the pointer. Right stick scrolls. "
                        + "A = left click, B = right click, X = middle click (Cross on PlayStation). "
                        + "Double-click by pressing A twice."
                )
            }

            Section {
                mappingRow("Left stick", "Move pointer")
                mappingRow("Left stick click (L3)", "Toggle virtual keyboard")
                mappingRow("Right stick", "Scroll (vertical / horizontal)")
                mappingRow("A (south)", "Left click")
                mappingRow("B (east)", "Right click")
                mappingRow("X (west)", "Middle click")
            } header: {
                Text("Default layout (Xbox / PlayStation)")
            }
        }
        .padding()
    }

    private func mappingRow(_ control: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(control)
            Spacer()
            Text(action)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

}

extension GCController: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
