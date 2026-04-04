import AppKit
import SwiftUI

/// In-app surface to verify pointer, clicks, scroll, and focus.
struct TestSurfaceView: View {
    @State private var singleClickCount = 0
    @State private var doubleClickCount = 0
    @State private var rightClickCount = 0
    @State private var middleClickCount = 0
    @State private var lastGesture = "—"
    @State private var testFieldText = "Focus here to test — keyboard follows any app’s text focus when enabled on Control."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Test surface")
                    .font(.title2.bold())

                Text(
                    "Use the gamepad: move over these targets, A to click, B for context menu, X for middle. "
                        + "Use the right stick to scroll this page."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                GroupBox("Gestures") {
                    VStack(alignment: .leading, spacing: 12) {
                        statRow("Single clicks", singleClickCount)
                        statRow("Double-clicks", doubleClickCount)
                        statRow("Right-clicks", rightClickCount)
                        statRow("Middle clicks", middleClickCount)
                        Divider()
                        Text("Last gesture: \(lastGesture)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 16) {
                    testButton(
                        title: "Single click",
                        subtitle: "Press A once",
                        color: .blue
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        singleClickCount += 1
                        lastGesture = "Single click"
                    }

                    testButton(
                        title: "Double-click",
                        subtitle: "Press A twice",
                        color: .cyan
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        doubleClickCount += 1
                        lastGesture = "Double-click"
                    }
                }

                testButton(
                    title: "Right-click",
                    subtitle: "B opens menu — pick the item",
                    color: .orange
                )
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Count right-click") {
                        rightClickCount += 1
                        lastGesture = "Right-click"
                    }
                }

                testButton(
                    title: "Middle click",
                    subtitle: "X on gamepad",
                    color: .purple
                )
                .contentShape(Rectangle())
                .overlay {
                    MiddleClickCatcher {
                        middleClickCount += 1
                        lastGesture = "Middle click"
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                GroupBox("Scroll region") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<24, id: \.self) { i in
                            Text("Line \(i + 1) — scroll with right stick to verify wheel events.")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Text field") {
                    TextField("Type here", text: $testFieldText)
                        .textFieldStyle(.roundedBorder)
                }
                Text(
                    "With “Auto keyboard” on (Control tab), focusing this field or Chrome’s URL bar opens the floating keyboard. "
                        + "Press L3 (left stick click) anytime to toggle it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func statRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .monospacedDigit()
                .fontWeight(.semibold)
        }
    }

    private func testButton(title: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.15))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Middle click via NSView

private struct MiddleClickCatcher: NSViewRepresentable {
    var onMiddle: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = MiddleClickNSView()
        v.onMiddle = onMiddle
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? MiddleClickNSView)?.onMiddle = onMiddle
    }

    final class MiddleClickNSView: NSView {
        var onMiddle: (() -> Void)?

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 2 {
                onMiddle?()
            }
            super.otherMouseDown(with: event)
        }
    }
}
