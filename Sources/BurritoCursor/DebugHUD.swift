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

    /// Bounded transition log — last N kind-level transitions surfaced in the HUD.
    private var transitions: [(t: Double, kind: String)] = []
    private let transitionLimit = 6
    /// We track the *kind* of the previous state (not its full label) so that
    /// per-frame scroll delta changes don't flood the transition log.
    private var lastStateKind: String?
    private var sessionStart: Double?

    /// Called whenever a new GestureState is emitted. Cheap; safe to call every frame.
    func update(
        state: GestureState,
        frameRateHz: Double,
        visionLatencyMs: Double,
        minConfidence: Double,
        landmarkCount: Int,
        rawPose: ClassifiedPose?,
        config: Config
    ) {
        let kind = Self.kindLabel(for: state)
        let display = Self.label(for: state)

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
        if let p = rawPose {
            rawText = String(
                format: "%@   I:%3d°  M:%3d°  R:%3d°  P:%3d°",
                String(describing: p.kind),
                Int(p.indexAngleDeg),
                Int(p.middleAngleDeg),
                Int(p.ringAngleDeg),
                Int(p.pinkyAngleDeg)
            )
        } else {
            rawText = "(no hand visible)"
        }

        let text = String(
            format: """
            state:        %@
            raw frame:    %@
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
              debounce out:  %d
              click enter:   %.0f°
              click exit:    %.0f°
            """,
            display, rawText, frameRateHz, visionLatencyMs, minConfidence, landmarkCount,
            recentLines.isEmpty ? "  (none yet)" : recentLines,
            config.sensitivity,
            config.deadzoneNormalized,
            config.debounceEntryFrames,
            config.debounceExitFrames,
            config.clickEnterAngleDeg,
            config.clickExitAngleDeg
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
        case .clickLatched: return "clickLatched"
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
        case .clickLatched: return "clickLatched"
        case .clicking: return "clicking"
        case .scrolling(let dy, _): return String(format: "scrolling(Δy=%.3f)", dy)
        case .degraded: return "degraded"
        }
    }
}
