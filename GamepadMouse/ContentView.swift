import GameController
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controllerService: ControllerService
    @EnvironmentObject private var inputEngine: InputEngine
    @EnvironmentObject private var gamepadUIState: GamepadUIState
    @EnvironmentObject private var keyboardManager: GlobalKeyboardManager
    @AppStorage("showDebugInfo") private var showDebugInfo = false
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                permissionBlock
                controllerBlock
                virtualKeyboardBlock
                mouseBlock
                controlsBlock
                advancedBlock
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Blocks (ScrollView avoids macOS Form two-column inset issues)

    @ViewBuilder
    private var permissionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Permission")
            if accessibilityTrusted {
                Label("Accessibility is enabled for Gamepad Mouse.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Allow this app to control your Mac")
                        .font(.headline)

                    Text(
                        "Gamepad Mouse needs Accessibility permission to move the pointer and send clicks. "
                            + "Use the buttons below to open Settings and enable this app."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if showDebugInfo {
                        Text(
                            "If you just rebuilt in Xcode: each new debug build is signed differently, so macOS treats it as a new app. "
                                + "Open Accessibility, remove every “Gamepad Mouse” entry (−), run this build again, then turn the new entry on."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(
                            "Signing with your Apple Development team in Xcode reduces how often this happens; "
                                + "ad hoc “Sign to Run Locally” resets trust whenever the binary changes."
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 12) {
                        Button("Open Accessibility Settings") {
                            AccessibilityGate.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Prompt Again") {
                            AccessibilityGate.promptIfNeeded()
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controllerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Controller")
            Picker("", selection: $controllerService.selectedObjectID) {
                Text("None").tag(Optional<ObjectIdentifier>.none)
                ForEach(controllerService.controllers) { c in
                    Text(controllerService.displayName(for: c))
                        .tag(Optional(ObjectIdentifier(c)))
                }
            }
            .labelsHidden()
            .accessibilityLabel("Controller")
            .disabled(controllerService.controllers.isEmpty)
            .frame(maxWidth: .infinity, alignment: .leading)

            if controllerService.isDiscoveringWireless {
                Label("Searching for wireless controllers…", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Search for wireless controllers") {
                controllerService.startWirelessDiscovery()
            }
            .disabled(controllerService.isDiscoveringWireless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var virtualKeyboardBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Virtual keyboard")
            Toggle("Auto-show keyboard when a text field is focused", isOn: $keyboardManager.autoShowOnTextFocus)
                .disabled(!accessibilityTrusted)

            Text("Press L3 (left stick click) anytime to show or hide the floating keyboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showDebugInfo {
                Text(
                    "Uses Accessibility to detect the focused field in any app. Secure password fields are skipped. "
                        + "Characters are sent as key events to the frontmost app."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var mouseBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Mouse")
            Toggle("Enable mouse control", isOn: $inputEngine.isEnabled)
                .disabled(!accessibilityTrusted)

            sliderBlock(
                title: "Pointer sensitivity",
                valueLabel: "\(Int(inputEngine.pointerSensitivity)) pt/s",
                value: $inputEngine.pointerSensitivity,
                range: 200...4000,
                step: 50
            )

            sliderBlock(
                title: "Scroll speed",
                valueLabel: "\(Int(inputEngine.scrollSpeed))",
                value: $inputEngine.scrollSpeed,
                range: 5...120,
                step: 1
            )

            sliderBlock(
                title: "Stick deadzone",
                valueLabel: "\(Int(inputEngine.deadzone * 100))%",
                value: $inputEngine.deadzone,
                range: 0.05...0.35,
                step: 0.01
            )

            if showDebugInfo {
                HStack(alignment: .firstTextBaseline) {
                    Text("Last input tick")
                    Spacer()
                    Text(inputEngine.lastTickSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                Text(
                    "Left stick moves the pointer; right stick scrolls. "
                        + "A = left click, B = right, X = middle (Cross on PlayStation). Double-click: A twice."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controlsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Controls")
            VStack(alignment: .leading, spacing: 10) {
                mappingRow("Left stick", "Move pointer")
                mappingRow("L3 (stick click)", "Toggle virtual keyboard")
                mappingRow("Right stick", "Scroll")
                mappingRow("A", "Left click")
                mappingRow("B", "Right click")
                mappingRow("X", "Middle click")
            }
            Text("Layout matches Apple’s extended gamepad profile (Xbox / PlayStation).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var advancedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Advanced")
            Toggle("Show debug info", isOn: $showDebugInfo)
            Text(
                showDebugInfo
                    ? "Technical notes, input tick status, and longer help text are visible."
                    : "Turn on to see rebuild/signing tips, input diagnostics, and extra detail."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func sliderBlock(
        title: String,
        valueLabel: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(valueLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func mappingRow(_ control: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(control)
                .frame(minWidth: 120, alignment: .leading)
            Spacer(minLength: 8)
            Text(action)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

}

extension GCController: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
