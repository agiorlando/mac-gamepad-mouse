import AppKit
import SwiftUI

/// In-app surface to verify pointer, clicks, scroll, and focus.
struct TestSurfaceView: View {
    @AppStorage("showDebugInfo") private var showDebugInfo = false
    @State private var singleClickCount = 0
    @State private var doubleClickCount = 0
    @State private var rightClickCount = 0
    @State private var middleClickCount = 0
    @State private var lastGesture = "—"
    @State private var testFieldText = "Type here to test the floating keyboard."

    private var scrollLineCount: Int { showDebugInfo ? 24 : 10 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test surface")
                        .font(.title2.bold())
                    Text(
                        "Move the pointer with the left stick, click targets with A / B / X, and scroll with the right stick."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Gestures")
                            .font(.subheadline.weight(.semibold))
                        statRow("Single clicks", singleClickCount)
                        statRow("Double-clicks", doubleClickCount)
                        statRow("Right-clicks", rightClickCount)
                        statRow("Middle clicks", middleClickCount)
                        if showDebugInfo {
                            Divider()
                            Text("Last gesture: \(lastGesture)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Targets")
                        .font(.subheadline.weight(.semibold))

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
                        subtitle: "Press B — use the menu",
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
                        subtitle: "Press X",
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
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scroll region")
                            .font(.subheadline.weight(.semibold))
                        ForEach(0..<scrollLineCount, id: \.self) { i in
                            Text(scrollLineLabel(i))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text field")
                            .font(.subheadline.weight(.semibold))
                        TextField("Type here", text: $testFieldText)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if showDebugInfo {
                    Text(
                        "With Auto-show keyboard enabled on the Control tab, focusing this field (or a field in another app) can open the floating keyboard. "
                            + "L3 toggles the keyboard anytime."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
    }

    private func scrollLineLabel(_ index: Int) -> String {
        let n = index + 1
        if showDebugInfo {
            return "Line \(n) — scroll with the right stick to verify wheel events."
        }
        return "Line \(n)"
    }

    private func statRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .monospacedDigit()
                .fontWeight(.semibold)
        }
        .font(.subheadline)
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
