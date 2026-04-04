import Combine
import GameController
import SwiftUI

// MARK: - Key model

enum KeyboardLayerID: Equatable {
    case letters, numbers, symbols
}

enum KeyAction: Equatable {
    case character(String)
    case shiftToggle
    case capsToggle
    case backspace
    case space
    case newline
    case layer(KeyboardLayerID)
    case dismiss
}

struct KeyDef: Identifiable, Equatable {
    let id: String
    let label: String
    let action: KeyAction
}

extension KeyAction {
    static var toNumbers: KeyAction { .layer(.numbers) }
    static var toLetters: KeyAction { .layer(.letters) }
    static var toSymbols: KeyAction { .layer(.symbols) }
}

// MARK: - Layouts

enum KeyboardLayout {

    static let letters: [[KeyDef]] = [
        keys("qwertyuiop", ids: "r0"),
        keys("asdfghjkl", ids: "r1"),
        [
            KeyDef(id: "sh", label: "⇧", action: .shiftToggle),
            KeyDef(id: "ca", label: "caps", action: .capsToggle),
        ] + keys("zxcvbnm", ids: "r2a") + [
            KeyDef(id: "bs", label: "⌫", action: .backspace),
        ],
        [
            KeyDef(id: "n12", label: "123", action: .toNumbers),
            KeyDef(id: "sym", label: "#+=", action: .toSymbols),
            KeyDef(id: "sp", label: "space", action: .space),
            KeyDef(id: "rt", label: "return", action: .newline),
            KeyDef(id: "dn", label: "Done", action: .dismiss),
        ],
    ]

    static let numbers: [[KeyDef]] = [
        keys("1234567890", ids: "n0"),
        stringRow([("-", "-"), ("/", "/"), (":", ":"), (";", ";"), ("(", "("), (")", ")"), ("$", "$"), ("&", "&"), ("@", "@"), ("\"", "\"")], idp: "n1"),
        stringRow([(".", "."), (",", ","), ("?", "?"), ("!", "!"), ("'", "'"), ("#", "#"), ("%", "%"), ("*", "*"), ("=", "="), ("⌫", "bs2")], idp: "n2", lastAction: .backspace),
        [
            KeyDef(id: "ab1", label: "ABC", action: .toLetters),
            KeyDef(id: "sy1", label: "#+=", action: .toSymbols),
            KeyDef(id: "sp2", label: "space", action: .space),
            KeyDef(id: "rt2", label: "return", action: .newline),
            KeyDef(id: "dn2", label: "Done", action: .dismiss),
        ],
    ]

    static let symbols: [[KeyDef]] = [
        stringRow([("`", "`"), ("~", "~"), ("_", "_"), ("+", "+"), ("[", "["), ("]", "]"), ("{", "{"), ("}", "}"), ("|", "|"), ("\\", "\\")], idp: "s0"),
        stringRow([("<", "<"), (">", ">"), ("€", "€"), ("£", "£"), ("¥", "¥"), ("^", "^"), ("°", "°"), ("•", "•"), ("…", "…"), ("⌫", "bs3")], idp: "s1", lastAction: .backspace),
        [
            KeyDef(id: "ab2", label: "ABC", action: .toLetters),
            KeyDef(id: "n22", label: "123", action: .toNumbers),
            KeyDef(id: "sp3", label: "space", action: .space),
            KeyDef(id: "rt3", label: "return", action: .newline),
            KeyDef(id: "dn3", label: "Done", action: .dismiss),
        ],
    ]

    private static func keys(_ s: String, ids: String) -> [KeyDef] {
        s.map { ch in
            let t = String(ch)
            return KeyDef(id: "\(ids)_\(t)", label: t, action: .character(t))
        }
    }

    private static func stringRow(
        _ pairs: [(String, String)],
        idp: String,
        lastAction: KeyAction? = nil
    ) -> [KeyDef] {
        pairs.enumerated().map { i, p in
            let isLast = i == pairs.count - 1
            if isLast, let lastAction {
                return KeyDef(id: "\(idp)_\(i)", label: p.0, action: lastAction)
            }
            return KeyDef(id: "\(idp)_\(i)", label: p.0, action: .character(p.1))
        }
    }
}

// MARK: - View model (gamepad polling)

@MainActor
final class OnScreenKeyboardViewModel: ObservableObject {

    @Published private(set) var rows: [[KeyDef]] = KeyboardLayout.letters
    @Published var selectionRow = 0
    @Published var selectionCol = 0
    @Published var layerKind: KeyboardLayerID = .letters
    @Published var capsLock = false
    @Published var shiftSticky = false
    @Published var echoedTail: String = ""
    @Published var hint = "L3 (stick click): toggle panel · D-pad: move · A: type · B: ⌫ hold · X: space · Y: return · LB: shift · RB: layer"

    private weak var controllerService: ControllerService?
    private var keyboardInjector: KeyboardInjector?
    private var timer: Timer?

    private var dpadUp = false
    private var dpadDown = false
    private var dpadLeft = false
    private var dpadRight = false
    private var aDown = false
    private var bDown = false
    private var bRepeatDeadline: Date?
    private let bRepeatInitial: TimeInterval = 0.4
    private let bRepeatInterval: TimeInterval = 0.055
    private var xDown = false
    private var yDown = false
    private var rbDown = false

    private let dpadThreshold: Float = 0.45

    func start(controllerService: ControllerService, keyboardInjector: KeyboardInjector) {
        self.controllerService = controllerService
        self.keyboardInjector = keyboardInjector
        echoedTail = ""
        stop()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.005
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()
        guard let pad = controllerService?.selectedController?.extendedGamepad else { return }
        let d = pad.dpad
        let up = d.yAxis.value > dpadThreshold
        let down = d.yAxis.value < -dpadThreshold
        let left = d.xAxis.value < -dpadThreshold
        let right = d.xAxis.value > dpadThreshold

        if up && !dpadUp { moveSelection(dy: -1) }
        if down && !dpadDown { moveSelection(dy: 1) }
        if left && !dpadLeft { moveSelection(dx: -1) }
        if right && !dpadRight { moveSelection(dx: 1) }
        dpadUp = up
        dpadDown = down
        dpadLeft = left
        dpadRight = right

        let shiftHeld = pad.leftShoulder.isPressed

        if pad.buttonA.isPressed && !aDown { activateSelectedKey(shiftHeld: shiftHeld) }
        aDown = pad.buttonA.isPressed

        let bPressed = pad.buttonB.isPressed
        if bPressed {
            if !bDown {
                backspace()
                bRepeatDeadline = now.addingTimeInterval(bRepeatInitial)
            } else if let deadline = bRepeatDeadline, now >= deadline {
                backspace()
                bRepeatDeadline = now.addingTimeInterval(bRepeatInterval)
            }
        } else {
            bRepeatDeadline = nil
        }
        bDown = bPressed

        if pad.buttonX.isPressed && !xDown { insert(" ") }
        xDown = pad.buttonX.isPressed

        if pad.buttonY.isPressed && !yDown { insert("\n") }
        yDown = pad.buttonY.isPressed

        if pad.rightShoulder.isPressed && !rbDown { cycleLayer() }
        rbDown = pad.rightShoulder.isPressed
    }

    private func moveSelection(dx: Int = 0, dy: Int = 0) {
        guard !rows.isEmpty else { return }
        if dy != 0 {
            let nr = (selectionRow + dy).clamped(to: 0...(rows.count - 1))
            if nr != selectionRow {
                selectionRow = nr
                selectionCol = min(selectionCol, max(0, rows[selectionRow].count - 1))
            }
            return
        }
        if dx != 0 {
            let row = rows[selectionRow]
            let nc = (selectionCol + dx).clamped(to: 0...(row.count - 1))
            selectionCol = nc
        }
    }

    private func activateSelectedKey(shiftHeld: Bool) {
        guard selectionRow < rows.count, selectionCol < rows[selectionRow].count else { return }
        let key = rows[selectionRow][selectionCol]
        switch key.action {
        case .character(let s):
            let odd = (shiftHeld ? 1 : 0) + (capsLock ? 1 : 0) + (shiftSticky ? 1 : 0)
            let upper = odd % 2 == 1
            if upper, s.count == 1, let ch = s.first, ch.isLetter {
                insert(s.uppercased())
            } else {
                insert(s)
            }
            if shiftSticky { shiftSticky = false }
        case .shiftToggle:
            shiftSticky.toggle()
        case .capsToggle:
            capsLock.toggle()
        case .backspace:
            backspace()
        case .space:
            insert(" ")
        case .newline:
            keyboardInjector?.tapReturnKey()
            echoedTail = String((echoedTail + "↵").suffix(120))
        case .layer(let id):
            setLayer(id)
        case .dismiss:
            onDismiss?()
        }
    }

    var onDismiss: (() -> Void)?

    private func setLayer(_ kind: KeyboardLayerID) {
        layerKind = kind
        switch kind {
        case .letters:
            rows = KeyboardLayout.letters
        case .numbers:
            rows = KeyboardLayout.numbers
        case .symbols:
            rows = KeyboardLayout.symbols
        }
        selectionRow = 0
        selectionCol = 0
    }

    private func cycleLayer() {
        switch layerKind {
        case .letters: setLayer(.numbers)
        case .numbers: setLayer(.symbols)
        case .symbols: setLayer(.letters)
        }
    }

    private func insert(_ s: String) {
        guard let inj = keyboardInjector else { return }
        inj.typeText(s)
        echoedTail = String((echoedTail + s).suffix(120))
    }

    private func backspace() {
        keyboardInjector?.tapBackwardDelete()
        if !echoedTail.isEmpty {
            echoedTail.removeLast()
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

