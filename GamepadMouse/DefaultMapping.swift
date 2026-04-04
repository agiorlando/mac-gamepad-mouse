import GameController

/// Normalized extended-gamepad layout (Xbox / PlayStation share semantic A/B/X/Y).
enum DefaultMapping {

    /// Apply circular deadzone; returns adjusted (x, y) in [-1, 1].
    static func stickAfterDeadzone(x: CGFloat, y: CGFloat, deadzone: CGFloat) -> (CGFloat, CGFloat) {
        let dz = max(0, min(deadzone, 0.95))
        let len = hypot(x, y)
        if len < dz || len == 0 { return (0, 0) }
        let scale = (len - dz) / (1 - dz)
        let nx = x / len
        let ny = y / len
        return (nx * scale, ny * scale)
    }

    /// Pointer delta from left stick: sensitivity is points per second at full deflection.
    static func pointerDelta(
        leftX: CGFloat,
        leftY: CGFloat,
        deadzone: CGFloat,
        sensitivityPointsPerSecond: Double,
        deltaTime: TimeInterval
    ) -> (CGFloat, CGFloat) {
        let (sx, sy) = stickAfterDeadzone(x: leftX, y: leftY, deadzone: deadzone)
        guard sx != 0 || sy != 0 else { return (0, 0) }
        let mag = hypot(sx, sy)
        let curve = pow(mag, 1.15)
        let scale = CGFloat((sensitivityPointsPerSecond * deltaTime) * Double(curve / max(mag, 0.0001)))
        // `yAxis` positive = stick up → move cursor up (positive AppKit screen Y).
        return (sx * scale, sy * scale)
    }

    /// Scroll delta from right stick; scrollSpeed scales pixels per frame at full tilt.
    static func scrollDelta(
        rightX: CGFloat,
        rightY: CGFloat,
        deadzone: CGFloat,
        scrollSpeed: CGFloat
    ) -> (CGFloat, CGFloat) {
        let (sx, sy) = stickAfterDeadzone(x: rightX, y: rightY, deadzone: deadzone)
        guard sx != 0 || sy != 0 else { return (0, 0) }
        // Pull stick toward user (positive raw Y) → scroll down (negative content direction is typical).
        return (sx * scrollSpeed, -sy * scrollSpeed)
    }
}
