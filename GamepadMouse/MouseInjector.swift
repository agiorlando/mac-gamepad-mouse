import AppKit
import CoreGraphics

/// Posts global pointer and scroll events. Requires Accessibility permission.
///
/// `NSEvent.mouseLocation` is in AppKit global space (origin bottom-left of the primary display, Y up).
/// `CGEvent` mouse positions expect Quartz global space (origin top-left of the primary display, Y down).
/// Mixing them causes mostly horizontal motion and odd cursor behavior.
final class MouseInjector {

    private let eventSource = CGEventSource(stateID: .hidSystemState)

    func currentMouseLocation() -> CGPoint {
        NSEvent.mouseLocation
    }

    /// Moves the cursor by delta in **AppKit** global coordinates (same space as `NSEvent.mouseLocation`).
    func movePointer(deltaX: CGFloat, deltaY: CGFloat) {
        let loc = NSEvent.mouseLocation
        let clampedNS = clampToScreens(x: loc.x + deltaX, y: loc.y + deltaY)
        let cgPoint = quartzGlobalPoint(fromAppKitGlobal: clampedNS)
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) else { return }
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    func leftMouseDown() {
        postMouse(type: .leftMouseDown, button: .left)
    }

    func leftMouseUp() {
        postMouse(type: .leftMouseUp, button: .left)
    }

    func rightMouseDown() {
        postMouse(type: .rightMouseDown, button: .right)
    }

    func rightMouseUp() {
        postMouse(type: .rightMouseUp, button: .right)
    }

    func otherMouseDown() {
        postMouse(type: .otherMouseDown, button: .center)
    }

    func otherMouseUp() {
        postMouse(type: .otherMouseUp, button: .center)
    }

    /// Vertical and horizontal scroll in pixel units (wheel1 = vertical, wheel2 = horizontal).
    func scrollPixels(deltaY: CGFloat, deltaX: CGFloat) {
        let vy = clampScroll(deltaY)
        let vx = clampScroll(deltaX)
        guard vy != 0 || vx != 0 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: vy,
            wheel2: vx,
            wheel3: 0
        ) else { return }
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func postMouse(type: CGEventType, button: CGMouseButton) {
        let locNS = NSEvent.mouseLocation
        let cgPoint = quartzGlobalPoint(fromAppKitGlobal: locNS)
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: cgPoint,
            mouseButton: button
        ) else { return }
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// AppKit global → Quartz global for `CGEvent` mouse positions (primary display–relative flip on Y).
    private func quartzGlobalPoint(fromAppKitGlobal location: CGPoint) -> CGPoint {
        guard let main = NSScreen.main ?? NSScreen.screens.first else {
            return location
        }
        // `main.frame` is in global AppKit coords; maxY is the top edge of the primary display.
        return CGPoint(x: location.x, y: main.frame.maxY - location.y)
    }

    private func clampToScreens(x: CGFloat, y: CGFloat) -> CGPoint {
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for screen in NSScreen.screens {
            let f = screen.frame
            minX = min(minX, f.minX)
            maxX = max(maxX, f.maxX)
            minY = min(minY, f.minY)
            maxY = max(maxY, f.maxY)
        }
        if minX > maxX {
            return CGPoint(x: x, y: y)
        }
        return CGPoint(
            x: x.clamped(to: minX...maxX),
            y: y.clamped(to: minY...maxY)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private func clampScroll(_ v: CGFloat) -> Int32 {
    Int32(Swift.min(100, Swift.max(-100, v.rounded())))
}
