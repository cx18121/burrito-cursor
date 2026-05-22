import AppKit
import CoreGraphics
import QuartzCore
import BurritoCursorCore

final class CursorController {
    private let config: Config
    private var oneEuroX: OneEuroFilter
    private var oneEuroY: OneEuroFilter
    private var lastMCP: BurritoCursorCore.NormalizedPoint?

    init(config: Config) {
        self.config = config
        self.oneEuroX = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
        self.oneEuroY = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
    }

    func handlePointing(at mcp: BurritoCursorCore.NormalizedPoint) {
        defer { lastMCP = mcp }
        guard let prev = lastMCP else { return }
        guard let screen = NSScreen.main else { return }

        let result = CursorMath.computeDelta(
            current: mcp,
            previous: prev,
            screenSize: (Double(screen.frame.width), Double(screen.frame.height)),
            config: config,
            timestamp: CACurrentMediaTime(),
            filterX: &oneEuroX,
            filterY: &oneEuroY
        )

        let cur = currentCursorPosition()
        let target = CGPoint(x: cur.x + result.dx, y: cur.y + result.dy)
        post(eventType: .mouseMoved, at: target)
    }

    /// Freeze cursor at current OS position; reset the smoothing filter so the next
    /// pointing frame starts clean (no leftover momentum).
    func freeze(at mcp: BurritoCursorCore.NormalizedPoint) {
        lastMCP = mcp
        oneEuroX = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
        oneEuroY = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
    }

    func mouseDown(at mcp: BurritoCursorCore.NormalizedPoint) {
        let cur = currentCursorPosition()
        post(eventType: .leftMouseDown, at: cur)
    }

    func mouseUp() {
        let cur = currentCursorPosition()
        post(eventType: .leftMouseUp, at: cur)
    }

    private func currentCursorPosition() -> CGPoint {
        guard let evt = CGEvent(source: nil) else { return .zero }
        return evt.location
    }

    private func post(eventType: CGEventType, at p: CGPoint) {
        guard let evt = CGEvent(mouseEventSource: nil,
                                mouseType: eventType,
                                mouseCursorPosition: p,
                                mouseButton: .left) else {
            NSLog("BurritoCursor: failed to create CGEvent (type=%d)", eventType.rawValue)
            return
        }
        evt.post(tap: .cghidEventTap)
    }
}
