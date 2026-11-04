import AppKit
import CoreGraphics

/// Moves the system cursor and synthesizes clicks.
///
/// AirPods only report motion at ~25 Hz, which looks choppy if applied directly.
/// Incoming deltas are accumulated and drained at 120 Hz with easing, so the
/// cursor glides smoothly between samples.
final class CursorController {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var timer: Timer?

    private var pendingX = 0.0
    private var pendingY = 0.0
    /// Sub-pixel position we're steering, so tiny movements aren't lost to rounding.
    private var position: CGPoint?

    /// Fraction of the remaining pending movement applied per 120 Hz tick.
    private let easing = 0.35

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func enqueue(dx: Double, dy: Double) {
        pendingX += dx
        pendingY += dy
    }

    func cancelPending() {
        pendingX = 0
        pendingY = 0
    }

    private func tick() {
        guard abs(pendingX) > 0.01 || abs(pendingY) > 0.01 else { return }

        var stepX = pendingX * easing
        var stepY = pendingY * easing
        if abs(pendingX) < 0.5 { stepX = pendingX }
        if abs(pendingY) < 0.5 { stepY = pendingY }
        pendingX -= stepX
        pendingY -= stepY

        let actual = currentLocation()
        // If the real mouse/trackpad moved the cursor, resync to it.
        var base = position ?? actual
        if hypot(base.x - actual.x, base.y - actual.y) > 2 {
            base = actual
        }

        let target = clampToScreens(CGPoint(x: base.x + stepX, y: base.y + stepY))
        position = target

        let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        )
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(stepX.rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(stepY.rounded()))
        event?.post(tap: .cghidEventTap)
    }

    // MARK: Clicks

    /// Clicks `button` `count` times (2 = double click).
    /// If `point` is given, the cursor jumps back there first. Earbud taps use
    /// this to click where the cursor was *before* the tap jolted the head.
    func click(_ button: CGMouseButton, count: Int = 1, at point: CGPoint? = nil) {
        var location = currentLocation()
        if let point {
            location = clampToScreens(point)
            cancelPending()
            position = location
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: location, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }

        let (downType, upType): (CGEventType, CGEventType) = switch button {
        case .right: (.rightMouseDown, .rightMouseUp)
        case .center: (.otherMouseDown, .otherMouseUp)
        default: (.leftMouseDown, .leftMouseUp)
        }

        for clickNumber in 1...max(count, 1) {
            let down = CGEvent(mouseEventSource: source, mouseType: downType,
                               mouseCursorPosition: location, mouseButton: button)
            let up = CGEvent(mouseEventSource: source, mouseType: upType,
                             mouseCursorPosition: location, mouseButton: button)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Helpers

    /// Current cursor location in global display coordinates (top-left origin).
    func currentLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return p }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let rects = ids.prefix(Int(count)).map { CGDisplayBounds($0) }

        if rects.contains(where: { $0.contains(p) }) { return p }

        // Outside every display: snap to the nearest point on the nearest display.
        var best = p
        var bestDist = Double.greatestFiniteMagnitude
        for r in rects {
            let c = CGPoint(x: min(max(p.x, r.minX), r.maxX - 1),
                            y: min(max(p.y, r.minY), r.maxY - 1))
            let d = hypot(c.x - p.x, c.y - p.y)
            if d < bestDist {
                bestDist = d
                best = c
            }
        }
        return best
    }
}
