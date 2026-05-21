import AppKit
import BurritoCursorCore

final class DebugHUD: NSWindowController {
    private let textView = NSTextView()
    private(set) var isShown = false

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 60, y: 60, width: 320, height: 200),
            styleMask: [.titled, .closable, .hudWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Burrito Debug"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        installViews()
    }

    private func installViews() {
        guard let cv = window?.contentView else { return }
        let scroll = NSScrollView(frame: cv.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width, .height]
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView
        cv.addSubview(scroll)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        isShown = true
    }

    override func close() {
        isShown = false
        super.close()
    }

    /// Called whenever a new GestureState is emitted. Cheap; safe to call every frame.
    func update(state: GestureState, frameRateHz: Double, visionLatencyMs: Double, minConfidence: Double) {
        let stateLabel: String
        switch state {
        case .idle: stateLabel = "idle"
        case .pointing: stateLabel = "pointing"
        case .clickLatched: stateLabel = "clickLatched"
        case .clicking: stateLabel = "clicking"
        case .scrolling(let dy, _): stateLabel = String(format: "scrolling(Δy=%.3f)", dy)
        case .degraded: stateLabel = "degraded"
        }
        let text = String(
            format: """
            state:        %@
            fps:          %.1f
            vision lat:   %.1f ms
            min conf:     %.2f
            """,
            stateLabel, frameRateHz, visionLatencyMs, minConfidence
        )
        DispatchQueue.main.async { [textView] in
            textView.string = text
        }
    }
}
