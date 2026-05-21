import Foundation

public final class GestureRecognizer {
    private let config: Config
    public private(set) var lastState: GestureState = .idle

    private struct Frame {
        let obs: HandObservation
        let pose: ClassifiedPose
    }
    private var window: [Frame] = []
    private let windowCapacity = 8

    private var lastAcceptedMCP: NormalizedPoint?

    public init(config: Config) {
        self.config = config
    }

    public func step(_ obs: HandObservation) -> GestureState {
        // Empty observation: no hand visible → idle, fresh acquisition required next time
        guard !obs.points.isEmpty else {
            resetToIdle()
            return lastState
        }

        // Confidence gate
        if obs.minConfidence < config.degradedConfidenceThreshold {
            transitionToDegraded()
            // Don't push low-confidence frames into the window — they'd contaminate debounce.
            // Clear the window so recovery requires fresh re-acquisition.
            window.removeAll()
            lastAcceptedMCP = nil
            return lastState
        }

        // Hand-jump continuity check
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

        // Classify and window
        let pose = PoseClassifier.classify(obs)
        window.append(Frame(obs: obs, pose: pose))
        if window.count > windowCapacity {
            window.removeFirst(window.count - windowCapacity)
        }

        lastState = computeNextState(currentPose: pose, currentObs: obs)
        return lastState
    }

    private func computeNextState(currentPose pose: ClassifiedPose, currentObs obs: HandObservation) -> GestureState {
        guard let mcp = obs.points[.indexMCP] else { return .idle }
        let entryFrames = config.debounceEntryFrames

        switch lastState {
        case .clicking:
            // Asymmetric exit: immediate release on angle restoration OR loss of pointing pose.
            if pose.indexAngleDeg > config.clickExitAngleDeg {
                return .pointing(point: mcp)
            }
            if pose.kind == .unknown {
                return .pointing(point: mcp) // back to pointing forces InputCoordinator's mouseUp on next apply
            }
            return .clicking(point: mcp)

        case .clickLatched:
            // Abandon if finger straightens
            if pose.indexAngleDeg > config.clickExitAngleDeg {
                return .pointing(point: mcp)
            }
            // Confirm only if every recent frame was a true click candidate (.indexBent).
            // Gating on .indexBent (not just angle) prevents a closed fist from confirming.
            let recent = window.suffix(entryFrames)
            if recent.count == entryFrames &&
                recent.allSatisfy({ $0.pose.kind == .indexBent }) {
                return .clicking(point: mcp)
            }
            return .clickLatched(point: mcp)

        case .pointing:
            // Click latch: index bend in the click window AND other fingers stay curled.
            // Requiring others-curled rejects fists and waves — only a real index-finger-only
            // bend (or the in-flight transition between pointing and indexBent) latches.
            let othersCurled = pose.middleAngleDeg < PoseClassifier.curledAngleDeg
                && pose.ringAngleDeg < PoseClassifier.curledAngleDeg
                && pose.pinkyAngleDeg < PoseClassifier.curledAngleDeg
            let intentionalIndexBend = pose.indexAngleDeg >= PoseClassifier.curledAngleDeg
                && pose.indexAngleDeg < config.clickExitAngleDeg
            if othersCurled && intentionalIndexBend && pose.kind != .scrolling {
                return .clickLatched(point: mcp)
            }
            // Scroll promotion: sustained scrolling pose
            let recent = window.suffix(entryFrames)
            if recent.count == entryFrames &&
                recent.allSatisfy({ $0.pose.kind == .scrolling }) {
                return .scrolling(deltaY: scrollDeltaY(twoMostRecent: true), point: mcp)
            }
            // Stay pointing while pointing pose continues
            if pose.kind == .pointing {
                return .pointing(point: mcp)
            }
            // Lost pose → idle (requires re-acquisition)
            return .idle

        case .scrolling:
            if pose.kind == .scrolling {
                return .scrolling(deltaY: scrollDeltaY(twoMostRecent: true), point: mcp)
            }
            if pose.kind == .pointing {
                return .pointing(point: mcp)
            }
            return .idle

        case .idle, .degraded:
            // Require N sustained frames to leave idle/degraded
            let recent = window.suffix(entryFrames)
            guard recent.count == entryFrames else { return .idle }
            if recent.allSatisfy({ $0.pose.kind == .pointing }) {
                return .pointing(point: mcp)
            }
            if recent.allSatisfy({ $0.pose.kind == .scrolling }) {
                return .scrolling(deltaY: scrollDeltaY(twoMostRecent: true), point: mcp)
            }
            return .idle
        }
    }

    /// Delta-y from the previous frame to the current frame, scaled by scrollSensitivity.
    /// Returns 0 if the window doesn't have at least two frames.
    private func scrollDeltaY(twoMostRecent: Bool) -> Double {
        let frames = twoMostRecent ? window.suffix(2) : window.suffix(window.count)
        guard frames.count >= 2 else { return 0 }
        let firstMCP = frames.first?.obs.points[.indexMCP]
        let lastMCP = frames.last?.obs.points[.indexMCP]
        guard let first = firstMCP, let last = lastMCP else { return 0 }
        return (last.y - first.y) * config.scrollSensitivity
    }

    private func resetToIdle() {
        window.removeAll()
        lastAcceptedMCP = nil
        lastState = .idle
    }

    private func transitionToDegraded() {
        let previous: GestureState.PreviousNonDegraded
        switch lastState {
        case .idle: previous = .idle
        case .pointing(let p): previous = .pointing(point: p)
        case .clickLatched(let p): previous = .clickLatched(point: p)
        case .clicking(let p): previous = .clicking(point: p)
        case .scrolling(_, let p): previous = .scrolling(point: p)
        case .degraded(let prev): previous = prev
        }
        lastState = .degraded(previous: previous)
    }
}
