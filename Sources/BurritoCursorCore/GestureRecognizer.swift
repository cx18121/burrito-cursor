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
        guard !obs.points.isEmpty else {
            resetToIdle()
            return lastState
        }

        if obs.minConfidence < config.degradedConfidenceThreshold {
            transitionToDegraded()
            window.removeAll()
            lastAcceptedMCP = nil
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
            // Asymmetric exit: immediate release on curl recovery or pose loss.
            if pose.index.curlRatio < config.clickReleaseCurlRatio {
                return .pointing(point: mcp)
            }
            if pose.kind == .unknown {
                // Forces InputCoordinator's mouseUp on next apply.
                return .pointing(point: mcp)
            }
            return .clicking(point: mcp)

        case .clickLatched:
            // Abandon if finger extends back to nearly straight.
            if pose.index.curlRatio < config.clickReleaseCurlRatio {
                return .pointing(point: mcp)
            }
            // Confirm if recent frames all have a clear bend (above confirm threshold).
            let recent = window.suffix(entryFrames)
            if recent.count == entryFrames &&
                recent.allSatisfy({ $0.pose.index.curlRatio > config.clickConfirmCurlRatio }) {
                return .clicking(point: mcp)
            }
            return .clickLatched(point: mcp)

        case .pointing:
            // Latch when the index just starts bending AND it's not already fully
            // curled (which would suggest a fist, not a click). Other fingers
            // must remain curled.
            let othersCurled = PoseClassifier.isCurled(pose.middle)
                && PoseClassifier.isCurled(pose.ring)
                && PoseClassifier.isCurled(pose.pinky)
            let indexInClickWindow = pose.index.curlRatio > config.clickStartCurlRatio
                && pose.index.curlRatio < PoseClassifier.curledCurlRatioMin
            if othersCurled && indexInClickWindow && pose.kind != .scrolling {
                return .clickLatched(point: mcp)
            }
            // Scroll promotion: sustained scrolling pose
            let recent = window.suffix(entryFrames)
            if recent.count == entryFrames &&
                recent.allSatisfy({ $0.pose.kind == .scrolling }) {
                return .scrolling(deltaY: scrollDeltaY(), point: mcp)
            }
            // Stay pointing while pointing pose continues
            if pose.kind == .pointing {
                return .pointing(point: mcp)
            }
            // Lost pose → idle (requires re-acquisition)
            return .idle

        case .scrolling:
            if pose.kind == .scrolling {
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
            if recent.allSatisfy({ $0.pose.kind == .scrolling }) {
                return .scrolling(deltaY: scrollDeltaY(), point: mcp)
            }
            return .idle
        }
    }

    private func scrollDeltaY() -> Double {
        let frames = window.suffix(2)
        guard frames.count >= 2,
              let first = frames.first?.obs.points[.indexMCP],
              let last = frames.last?.obs.points[.indexMCP] else { return 0 }
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
