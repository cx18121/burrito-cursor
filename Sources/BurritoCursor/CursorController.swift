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

        var dx = mcp.x - prev.x
        // Vision y is bottom-left origin; CGEvent cursor y is top-left → invert
        var dy = -(mcp.y - prev.y)

        if abs(dx) < config.deadzoneNormalized { dx = 0 }
        if abs(dy) < config.deadzoneNormalized { dy = 0 }

        guard let screen = NSScreen.main else { return }
        let screenW = screen.frame.width
        let screenH = screen.frame.height

        // 0.2 = ~20cm arm sweep maps to full primary display at sensitivity 1.0
        let scaleX = screenW * config.sensitivity / 0.2
        let scaleY = screenH * config.sensitivity / 0.2

        let now = CACurrentMediaTime()
        let sx = oneEuroX.filter(dx * scaleX, timestampSec: now)
        let sy = oneEuroY.filter(dy * scaleY, timestampSec: now)

        let cur = currentCursorPosition()
        let target = CGPoint(x: cur.x + sx, y: cur.y + sy)
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
                                mouseButton: .left) else { return }
        evt.post(tap: .cghidEventTap)
    }
}
