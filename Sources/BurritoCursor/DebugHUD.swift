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

    /// Bounded transition log — last N transitions surfaced in the HUD.
    private var transitions: [(t: Double, label: String)] = []
    private let transitionLimit = 6
    private var lastStateLabel: String?
    private var sessionStart: Double?

    /// Called whenever a new GestureState is emitted. Cheap; safe to call every frame.
    func update(
        state: GestureState,
        frameRateHz: Double,
        visionLatencyMs: Double,
        minConfidence: Double,
        landmarkCount: Int,
        config: Config
    ) {
        let label = Self.label(for: state)

        if sessionStart == nil { sessionStart = CACurrentMediaTime() }
        if label != lastStateLabel {
            let t = CACurrentMediaTime() - (sessionStart ?? 0)
            transitions.append((t, label))
            if transitions.count > transitionLimit {
                transitions.removeFirst(transitions.count - transitionLimit)
            }
            lastStateLabel = label
        }

        let recentLines = transitions
            .map { String(format: "  [%5.2fs] %@", $0.t, $0.label) }
            .joined(separator: "\n")

        let text = String(
            format: """
            state:        %@
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
            label, frameRateHz, visionLatencyMs, minConfidence, landmarkCount,
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
