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
            forceReleaseLocked()
        case .pointing(let p):
            forceReleaseLocked()
            cursorController?.handlePointing(at: p)
        case .clickLatched(let p):
            forceReleaseLocked()
            cursorController?.freeze(at: p)
        case .clicking(let p):
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
