import Foundation

public final class GestureRecognizer {
    private let config: Config
    public private(set) var lastState: GestureState = .idle
    /// Pose classification from the most recent `step()` call, or `nil` when there
    /// was no valid hand (empty observation or below-threshold confidence).
    /// Exposed so callers (HUD, preview) don't re-run `PoseClassifier.classify`.
    public private(set) var lastPose: ClassifiedPose?

    private struct Frame {
        let obs: HandObservation
        let pose: ClassifiedPose
    }
    private var window: [Frame] = []
    private let windowCapacity = 8

    private var lastAcceptedMCP: NormalizedPoint?

    /// Tracks current pinch via hysteresis so single-frame flicker doesn't toggle clicks.
    private var pinching = false

    public init(config: Config) {
        self.config = config
    }

    public func step(_ obs: HandObservation) -> GestureState {
        guard !obs.points.isEmpty else {
            resetToIdle()
            lastPose = nil
            return lastState
        }

        if obs.minConfidence < config.degradedConfidenceThreshold {
            window.removeAll()
            lastAcceptedMCP = nil
            pinching = false
            lastPose = nil
            lastState = .degraded
            return lastState
        }

        if let prev = lastAcceptedMCP, let cur = obs.points[.indexMCP] {
            let dx = cur.x - prev.x
            let dy = cur.y - prev.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist > config.handJumpRejectionFraction {
                resetToIdle()
                return lastState
            }
        }
        if let cur = obs.points[.indexMCP] {
            lastAcceptedMCP = cur
        }

        let pose = PoseClassifier.classify(obs)
        lastPose = pose
        window.append(Frame(obs: obs, pose: pose))
        if window.count > windowCapacity {
            window.removeFirst(window.count - windowCapacity)
        }

        // Update pinch state with hysteresis (independent of pose state machine).
        if pinching {
            if pose.pinchDistance > config.pinchEndDistance { pinching = false }
        } else {
            if pose.pinchDistance < config.pinchStartDistance { pinching = true }
        }

        lastState = computeNextState(currentPose: pose, currentObs: obs)
        return lastState
    }

    private func computeNextState(currentPose pose: ClassifiedPose, currentObs obs: HandObservation) -> GestureState {
        guard let mcp = obs.points[.indexMCP] else { return .idle }
        let entryFrames = config.debounceEntryFrames

        switch lastState {
        case .clicking:
            // Pinch hysteresis is the ONLY click gate. Pose flicker (the
            // classifier briefly returning .unknown or .openPalm because a
            // non-pinch finger moved mid-drag) used to drop us to .pointing
            // here, which made InputCoordinator emit mouseUp+mouseDown — a
            // phantom release-and-repress that broke drag-select. Stay in
            // .clicking until the pinch actually releases.
            if !pinching { return .pointing(point: mcp) }
            return .clicking(point: mcp)

        case .pointing:
            // Pinch detected → click immediately. No latch, no debounce — the
            // hysteresis on pinch start/end is what protects against flicker.
            if pinching && pose.kind == .pointing {
                return .clicking(point: mcp)
            }
            // Sustained open palm → scroll
            let recent = window.suffix(entryFrames)
            if recent.count == entryFrames &&
                recent.allSatisfy({ $0.pose.kind == .openPalm }) {
                return .scrolling(deltaY: scrollDeltaY(), point: mcp)
            }
            if pose.kind == .pointing {
                return .pointing(point: mcp)
            }
            return .idle

        case .scrolling:
            if pose.kind == .openPalm {
                return .scrolling(deltaY: scrollDeltaY(), point: mcp)
            }
            if pose.kind == .pointing {
                return .pointing(point: mcp)
            }
            return .idle

        case .idle, .degraded:
            let recent = window.suffix(entryFrames)
            guard recent.count == entryFrames else { return .idle }
            if recent.allSatisfy({ $0.pose.kind == .pointing }) {
                return .pointing(point: mcp)
            }
            if recent.allSatisfy({ $0.pose.kind == .openPalm }) {
                return .scrolling(deltaY: scrollDeltaY(), point: mcp)
            }
            return .idle
        }
    }

    private func scrollDeltaY() -> Double {
        let frames = window.suffix(2)
        guard frames.count >= 2,
              let first = frames.first?.obs.points[.indexMCP] ?? frames.first?.obs.points[.middleMCP],
              let last = frames.last?.obs.points[.indexMCP] ?? frames.last?.obs.points[.middleMCP] else {
            return 0
        }
        return (last.y - first.y) * config.scrollSensitivity
    }

    private func resetToIdle() {
        window.removeAll()
        lastAcceptedMCP = nil
        pinching = false
        lastState = .idle
        lastPose = nil
    }
}
