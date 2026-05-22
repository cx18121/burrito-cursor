import Foundation

/// Multiple per-frame signals computed for one finger. The classifier combines
/// these into `isExtended`/`isCurled` decisions; the recognizer also reads
/// `curlRatio` directly for click-state transitions.
public struct FingerSignals: Equatable {
    /// 2D angle at the PIP joint (MCP → PIP → TIP). 180° = straight, 0° = folded.
    /// Kept for HUD display and legacy callers; classification no longer uses this
    /// as the primary signal because 2D angles foreshorten badly when fingers
    /// point toward/away from the camera.
    public let angleDeg: Double

    /// Sum of segment lengths along the finger divided by the straight-line
    /// MCP→TIP distance. 1.0 = straight, ∞ = fully folded back. This is the
    /// **primary** classification signal — it's orientation-invariant in 2D.
    public let curlRatio: Double

    /// |TIP − MCP| / palm-scale. Lets you reason about absolute finger
    /// extension relative to the hand size. Secondary signal, mostly for HUD.
    public let chordNormalized: Double
}

public struct ClassifiedPose: Equatable {
    public enum Kind: Equatable {
        case pointing       // index extended, middle/ring/pinky curled
        case scrolling      // index + middle extended, ring/pinky curled
        case indexBent      // others curled, index neither fully extended nor fully curled — click candidate (display label)
        case unknown
    }
    public let kind: Kind
    public let index: FingerSignals
    public let middle: FingerSignals
    public let ring: FingerSignals
    public let pinky: FingerSignals

    // Legacy accessors so callers and tests don't break.
    public var indexAngleDeg: Double { index.angleDeg }
    public var middleAngleDeg: Double { middle.angleDeg }
    public var ringAngleDeg: Double { ring.angleDeg }
    public var pinkyAngleDeg: Double { pinky.angleDeg }
}

public enum PoseClassifier {
    /// Curl ratio below this → finger is extended (nearly straight).
    public static let extendedCurlRatioMax = 1.10
    /// Curl ratio above this → finger is curled (folded). Above this we treat
    /// the finger as "part of a fist," not a click candidate.
    public static let curledCurlRatioMin = 1.60

    // Legacy angle thresholds — still exposed for callers that haven't moved
    // off the angle-based API. Not used internally by classify().
    public static let extendedAngleDeg = 150.0
    public static let curledAngleDeg = 120.0
    public static let clickRawThresholdDeg = 145.0

    public static func classify(_ obs: HandObservation) -> ClassifiedPose {
        let palmScale = computePalmScale(obs)
        let index = signals(mcp: .indexMCP,  pip: .indexPIP,  dip: .indexDIP,  tip: .indexTip,  obs: obs, palmScale: palmScale)
        let middle = signals(mcp: .middleMCP, pip: .middlePIP, dip: .middleDIP, tip: .middleTip, obs: obs, palmScale: palmScale)
        let ring = signals(mcp: .ringMCP,   pip: .ringPIP,   dip: .ringDIP,   tip: .ringTip,   obs: obs, palmScale: palmScale)
        let pinky = signals(mcp: .pinkyMCP,  pip: .pinkyPIP,  dip: .pinkyDIP,  tip: .pinkyTip,  obs: obs, palmScale: palmScale)

        let indexExt = isExtended(index)
        let indexCurled = isCurled(index)
        let middleExt = isExtended(middle)
        let middleCurled = isCurled(middle)
        let ringCurled = isCurled(ring)
        let pinkyCurled = isCurled(pinky)

        let kind: ClassifiedPose.Kind
        if indexExt, middleCurled, ringCurled, pinkyCurled {
            kind = .pointing
        } else if indexExt, middleExt, ringCurled, pinkyCurled {
            kind = .scrolling
        } else if !indexExt, !indexCurled, middleCurled, ringCurled, pinkyCurled {
            // Index in the transition zone (bent but not fully curled), others
            // stay curled — true click candidate. Fully-curled fists fall to
            // .unknown instead, so they don't trigger spurious "click" labels.
            kind = .indexBent
        } else {
            kind = .unknown
        }
        return ClassifiedPose(kind: kind, index: index, middle: middle, ring: ring, pinky: pinky)
    }

    /// True if the finger reads as nearly straight.
    public static func isExtended(_ s: FingerSignals) -> Bool {
        s.curlRatio < extendedCurlRatioMax
    }

    /// True if the finger reads as fully folded back (fist-like).
    public static func isCurled(_ s: FingerSignals) -> Bool {
        s.curlRatio > curledCurlRatioMin
    }

    // MARK: - Geometry

    private static func computePalmScale(_ obs: HandObservation) -> Double {
        // Primary: wrist → middleMCP distance (palm length). Stable across
        // rotations where indexMCP and pinkyMCP can collapse onto each other.
        if let w = obs.points[.wrist], let m = obs.points[.middleMCP] {
            let d = distance(w, m)
            if d > 1e-3 { return d }
        }
        // Fallback: indexMCP → pinkyMCP (palm width)
        if let i = obs.points[.indexMCP], let p = obs.points[.pinkyMCP] {
            let d = distance(i, p)
            if d > 1e-3 { return d }
        }
        return 0.1
    }

    private static func signals(
        mcp: JointName, pip: JointName, dip: JointName, tip: JointName,
        obs: HandObservation, palmScale: Double
    ) -> FingerSignals {
        guard let m = obs.points[mcp], let p = obs.points[pip], let t = obs.points[tip] else {
            return FingerSignals(angleDeg: 0, curlRatio: 1.0, chordNormalized: 0)
        }
        // Path: sum of segments MCP→PIP[→DIP]→TIP. Uses 3 segments if DIP is
        // present (real Vision data), 2 otherwise (synthetic test data).
        var path = distance(m, p) + distance(p, t)
        if let d = obs.points[dip] {
            path = distance(m, p) + distance(p, d) + distance(d, t)
        }
        let chord = distance(m, t)
        let curlRatio = chord > 1e-6 ? path / chord : .infinity
        let chordNormalized = palmScale > 1e-6 ? chord / palmScale : 0
        let angleDeg = computeAngleDeg(mcp: m, pip: p, tip: t)
        return FingerSignals(angleDeg: angleDeg, curlRatio: curlRatio, chordNormalized: chordNormalized)
    }

    private static func distance(_ a: NormalizedPoint, _ b: NormalizedPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func computeAngleDeg(
        mcp m: NormalizedPoint, pip p: NormalizedPoint, tip t: NormalizedPoint
    ) -> Double {
        let v1x = m.x - p.x, v1y = m.y - p.y
        let v2x = t.x - p.x, v2y = t.y - p.y
        let dot = v1x * v2x + v1y * v2y
        let mag1 = (v1x * v1x + v1y * v1y).squareRoot()
        let mag2 = (v2x * v2x + v2y * v2y).squareRoot()
        guard mag1 > 1e-9, mag2 > 1e-9 else { return 0 }
        let cosA = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosA) * 180.0 / .pi
    }

    /// Legacy public API for the 2D angle on a single finger.
    public static func fingerAngleDeg(
        _ obs: HandObservation,
        mcp: JointName, pip: JointName, tip: JointName
    ) -> Double {
        guard let m = obs.points[mcp], let p = obs.points[pip], let t = obs.points[tip] else {
            return 0
        }
        return computeAngleDeg(mcp: m, pip: p, tip: t)
    }
}
