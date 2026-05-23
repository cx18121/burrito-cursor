import AppKit
import QuartzCore
import BurritoCursorCore

final class DebugHUD: NSWindowController {
    private let textView = NSTextView()
    private(set) var isShown = false

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 60, y: 60, width: 360, height: 440),
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

    /// Shown to the user when the cursor pipeline isn't running — without this
    /// the HUD just sits blank and looks broken.
    func showDisabledState() {
        let text = """
        Cursor is disabled.

        Click 🌯 → Enable Cursor (or ⌃⌥H) to start
        the camera and see live data here.

        Once enabled this panel shows:
          • current gesture state
          • per-finger curl ratios
          • frame rate + Vision latency
          • detected landmark count
          • recent state transitions
        """
        DispatchQueue.main.async { [textView] in
            textView.string = text
        }
    }

    /// Bounded transition log — last N kind-level transitions surfaced in the HUD.
    private var transitions: [(t: Double, kind: String)] = []
    private let transitionLimit = 6
    /// We track the *kind* of the previous state (not its full label) so that
    /// per-frame scroll delta changes don't flood the transition log.
    private var lastStateKind: String?
    private var sessionStart: Double?

    /// Called whenever a new snapshot is available. Cheap; safe to call every frame.
    func update(snapshot s: PipelineSnapshot, config: Config) {
        let kind = Self.kindLabel(for: s.state)
        let display = Self.label(for: s.state)

        if sessionStart == nil { sessionStart = CACurrentMediaTime() }
        if kind != lastStateKind {
            let t = CACurrentMediaTime() - (sessionStart ?? 0)
            transitions.append((t, kind))
            if transitions.count > transitionLimit {
                transitions.removeFirst(transitions.count - transitionLimit)
            }
            lastStateKind = kind
        }

        let recentLines = transitions
            .map { String(format: "  [%5.2fs] %@", $0.t, $0.kind) }
            .joined(separator: "\n")

        let rawText: String
        let curlText: String
        let pinchText: String
        if let p = s.pose {
            rawText = String(
                format: "%@   T:%.2f  I:%.2f  M:%.2f  R:%.2f  P:%.2f",
                String(describing: p.kind),
                p.thumb.curlRatio,
                p.index.curlRatio,
                p.middle.curlRatio,
                p.ring.curlRatio,
                p.pinky.curlRatio
            )
            curlText = String(
                format: "angles:  T:%3d°  I:%3d°  M:%3d°",
                Int(p.thumb.angleDeg),
                Int(p.indexAngleDeg),
                Int(p.middleAngleDeg)
            )
            pinchText = String(format: "pinch:   %.2f", p.pinchDistance)
        } else {
            rawText = "(no hand visible)"
            curlText = ""
            pinchText = ""
        }

        let text = String(
            format: """
            state:        %@
            raw frame:    %@
            %@
            %@
            fps:          %.1f
            vision lat:   %.1f ms
            min conf:     %.2f
            landmarks:    %d

            transitions:
            %@

            config:
              sensitivity:   %.2f
              deadzone:      %.4f
              debounce in:   %d
              pinch start:   %.2f
              pinch end:     %.2f
            """,
            display, rawText, curlText, pinchText,
            s.frameRateHz, s.visionLatencyMs, s.minConfidence, s.landmarkCount,
            recentLines.isEmpty ? "  (none yet)" : recentLines,
            config.sensitivity,
            config.deadzoneNormalized,
            config.debounceEntryFrames,
            config.pinchStartDistance,
            config.pinchEndDistance
        )
        DispatchQueue.main.async { [textView] in
            textView.string = text
        }
    }

    /// Stable identity of the state — does NOT change frame-to-frame for scrolling.
    /// Used for the transition log so per-frame scroll deltas don't flood it.
    private static func kindLabel(for state: GestureState) -> String {
        switch state {
        case .idle: return "idle"
        case .pointing: return "pointing"
        case .clicking: return "clicking"
        case .scrolling: return "scrolling"
        case .degraded: return "degraded"
        }
    }

    /// Full display label, including dynamic values like scroll delta.
    private static func label(for state: GestureState) -> String {
        switch state {
        case .idle: return "idle"
        case .pointing: return "pointing"
        case .clicking: return "clicking"
        case .scrolling(let dy, _): return String(format: "scrolling(Δy=%.3f)", dy)
        case .degraded: return "degraded"
        }
    }
}
