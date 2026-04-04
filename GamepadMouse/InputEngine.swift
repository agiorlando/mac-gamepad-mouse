import AppKit
import Combine
import Foundation
import GameController

/// 60 Hz poll: maps extended gamepad → mouse injector (and D-pad arrows when the OSK is closed).
final class InputEngine: ObservableObject {

    @Published var isEnabled = false
    @Published var pointerSensitivity: Double = 1200
    @Published var scrollSpeed: Double = 35
    @Published var deadzone: Double = 0.12

    @Published private(set) var lastTickSummary: String = ""

    private let controllerService: ControllerService
    private let mouse: MouseInjector
    private let keyboard: KeyboardInjector
    private let uiState: GamepadUIState
    private var timer: Timer?

    private var leftDown = false
    private var rightDown = false
    private var otherDown = false
    private var lastTickTime: Date?

    private let dpadThreshold: Float = 0.45
    private var dpadUp = false
    private var dpadDown = false
    private var dpadLeft = false
    private var dpadRight = false
    private var dpadRepeatDeadline: [String: Date] = [:]
    private let dpadRepeatInitial: TimeInterval = 0.35
    private let dpadRepeatInterval: TimeInterval = 0.08

    init(controllerService: ControllerService, mouse: MouseInjector, keyboard: KeyboardInjector, uiState: GamepadUIState) {
        self.controllerService = controllerService
        self.mouse = mouse
        self.keyboard = keyboard
        self.uiState = uiState
    }

    deinit {
        stopTimer()
        releaseAllButtons()
    }

    func updateAccessibilityTrustState() {
        if !AccessibilityGate.isTrusted {
            isEnabled = false
        }
    }

    func startStopTimerIfNeeded() {
        stopTimer()
        guard isEnabled, AccessibilityGate.isTrusted else { return }
        lastTickTime = nil
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.005
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        releaseAllButtons()
        lastTickTime = nil
        dpadRepeatDeadline.removeAll()
    }

    func onEnabledChanged() {
        if isEnabled {
            if AccessibilityGate.isTrusted {
                startStopTimerIfNeeded()
            } else {
                isEnabled = false
            }
        } else {
            stopTimer()
        }
    }

    private func tick() {
        guard isEnabled, AccessibilityGate.isTrusted else { return }
        guard let pad = controllerService.selectedController?.extendedGamepad else {
            lastTickSummary = "No extended gamepad"
            return
        }

        let now = Date()
        let dt: TimeInterval
        if let prev = lastTickTime {
            dt = min(max(now.timeIntervalSince(prev), 1.0 / 240.0), 0.1)
        } else {
            dt = 1.0 / 60.0
        }
        lastTickTime = now

        let lx = CGFloat(pad.leftThumbstick.xAxis.value)
        let ly = CGFloat(pad.leftThumbstick.yAxis.value)
        let rx = CGFloat(pad.rightThumbstick.xAxis.value)
        let ry = CGFloat(pad.rightThumbstick.yAxis.value)

        let dz = CGFloat(deadzone)
        let (dx, dy) = DefaultMapping.pointerDelta(
            leftX: lx,
            leftY: ly,
            deadzone: dz,
            sensitivityPointsPerSecond: pointerSensitivity,
            deltaTime: dt
        )
        if dx != 0 || dy != 0 {
            mouse.movePointer(deltaX: dx, deltaY: dy)
        }

        let (svx, svy) = DefaultMapping.scrollDelta(
            rightX: rx,
            rightY: ry,
            deadzone: dz,
            scrollSpeed: CGFloat(scrollSpeed)
        )
        if svx != 0 || svy != 0 {
            mouse.scrollPixels(deltaY: svy, deltaX: svx)
        }

        let osk = uiState.onScreenKeyboardVisible

        if !osk {
            handleDpadArrows(dpad: pad.dpad, now: now)
            updateButton(pad.buttonA, wasDown: &leftDown, down: mouse.leftMouseDown, up: mouse.leftMouseUp)
            updateButton(pad.buttonB, wasDown: &rightDown, down: mouse.rightMouseDown, up: mouse.rightMouseUp)
            updateButton(pad.buttonX, wasDown: &otherDown, down: mouse.otherMouseDown, up: mouse.otherMouseUp)
        } else {
            if leftDown { mouse.leftMouseUp(); leftDown = false }
            if rightDown { mouse.rightMouseUp(); rightDown = false }
            if otherDown { mouse.otherMouseUp(); otherDown = false }
        }

        var parts: [String] = []
        if dx != 0 || dy != 0 { parts.append("move") }
        if svx != 0 || svy != 0 { parts.append("scroll") }
        if !osk, pad.buttonA.isPressed || pad.buttonB.isPressed || pad.buttonX.isPressed {
            parts.append("buttons")
        }
        if !osk, dpadUp || dpadDown || dpadLeft || dpadRight { parts.append("dpad") }
        lastTickSummary = parts.isEmpty ? "idle" : parts.joined(separator: ", ")
    }

    private func handleDpadArrows(dpad: GCControllerDirectionPad, now: Date) {
        let up = dpad.yAxis.value > dpadThreshold
        let down = dpad.yAxis.value < -dpadThreshold
        let left = dpad.xAxis.value < -dpadThreshold
        let right = dpad.xAxis.value > dpadThreshold

        fireArrowIfNeeded(id: "u", pressed: up, wasPressed: dpadUp, arrow: .up, now: now)
        fireArrowIfNeeded(id: "d", pressed: down, wasPressed: dpadDown, arrow: .down, now: now)
        fireArrowIfNeeded(id: "l", pressed: left, wasPressed: dpadLeft, arrow: .left, now: now)
        fireArrowIfNeeded(id: "r", pressed: right, wasPressed: dpadRight, arrow: .right, now: now)

        dpadUp = up
        dpadDown = down
        dpadLeft = left
        dpadRight = right

        if !up { dpadRepeatDeadline["u"] = nil }
        if !down { dpadRepeatDeadline["d"] = nil }
        if !left { dpadRepeatDeadline["l"] = nil }
        if !right { dpadRepeatDeadline["r"] = nil }
    }

    private func fireArrowIfNeeded(
        id: String,
        pressed: Bool,
        wasPressed: Bool,
        arrow: KeyboardInjector.Arrow,
        now: Date
    ) {
        guard pressed else { return }
        if !wasPressed {
            keyboard.tapArrow(arrow)
            dpadRepeatDeadline[id] = now.addingTimeInterval(dpadRepeatInitial)
            return
        }
        if let deadline = dpadRepeatDeadline[id], now >= deadline {
            keyboard.tapArrow(arrow)
            dpadRepeatDeadline[id] = now.addingTimeInterval(dpadRepeatInterval)
        }
    }

    private func updateButton(
        _ button: GCControllerButtonInput,
        wasDown: inout Bool,
        down: () -> Void,
        up: () -> Void
    ) {
        let pressed = button.isPressed
        if pressed && !wasDown { down() }
        if !pressed && wasDown { up() }
        wasDown = pressed
    }

    private func releaseAllButtons() {
        if leftDown { mouse.leftMouseUp(); leftDown = false }
        if rightDown { mouse.rightMouseUp(); rightDown = false }
        if otherDown { mouse.otherMouseUp(); otherDown = false }
    }
}
