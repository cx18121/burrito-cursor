import AppKit
import CoreGraphics
import BurritoCursorCore

final class InputCoordinator {
    private var mouseDownOutstanding = false
    private let lock = NSLock()

    var cursorController: CursorController?
    var scrollController: ScrollController?

    func apply(state: GestureState) {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .idle, .degraded:
            // Hand-loss path: release any held click AND clear the cursor's
            // last-position anchor so the next .pointing frame doesn't compute
            // a huge delta from a stale position (cursor-jump-on-recovery).
            forceReleaseLocked()
            cursorController?.reset()
        case .pointing(let p):
            forceReleaseLocked()
            cursorController?.handlePointing(at: p)
        case .clicking(let p):
            // Pinch is binary — emit mouseDown on first .clicking frame, hold it
            // until we exit .clicking (which fires mouseUp via forceReleaseLocked).
            if !mouseDownOutstanding {
                cursorController?.mouseDown(at: p)
                mouseDownOutstanding = true
            }
        case .scrolling(let dy, _):
            forceReleaseLocked()
            scrollController?.scroll(deltaY: dy)
        }
    }

    /// Idempotent. Call from any lifecycle event that might break the click pairing
    /// (toggle off, sleep, lid close, permission loss, app quit).
    func forceRelease() {
        lock.lock()
        defer { lock.unlock() }
        forceReleaseLocked()
    }

    private func forceReleaseLocked() {
        if mouseDownOutstanding {
            cursorController?.mouseUp()
            mouseDownOutstanding = false
        }
    }
}
