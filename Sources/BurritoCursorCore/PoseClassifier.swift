import Foundation

public struct ClassifiedPose: Equatable {
    public enum Kind: Equatable {
        case pointing       // index extended, others curled
        case scrolling      // index + middle extended, ring + pinky curled
        case indexBent      // pointing-shape but index angle below click threshold (click candidate)
        case unknown        // anything else
    }
    public let kind: Kind
    public let indexAngleDeg: Double
    public let middleAngleDeg: Double
    public let ringAngleDeg: Double
    public let pinkyAngleDeg: Double
}

public enum PoseClassifier {
    // Loosened from initial 160/110/140 — real hands rarely fully extend (most
    // "extended" fingers sit at 150-170°) and rarely fully curl (most "curled"
    // fingers sit at 90-130°). Wider bands = more forgiving classification.
    public static let extendedAngleDeg = 150.0
    public static let curledAngleDeg = 120.0
    public static let clickRawThresholdDeg = 145.0

    /// Per-frame raw classification. The state machine in `GestureRecognizer`
    /// applies hysteresis using `Config.clickEnterAngleDeg` / `clickExitAngleDeg`.
    public static func classify(_ obs: HandObservation) -> ClassifiedPose {
        let idx = fingerAngleDeg(obs, mcp: .indexMCP, pip: .indexPIP, tip: .indexTip)
        let mid = fingerAngleDeg(obs, mcp: .middleMCP, pip: .middlePIP, tip: .middleTip)
        let ring = fingerAngleDeg(obs, mcp: .ringMCP, pip: .ringPIP, tip: .ringTip)
        let pky = fingerAngleDeg(obs, mcp: .pinkyMCP, pip: .pinkyPIP, tip: .pinkyTip)

        let indexExtended = idx >= extendedAngleDeg
        // A "click bend" is index partially bent — not fully curled. Distinguishes the
        // click gesture from a closed fist, which is .unknown.
        let indexClickBent = idx >= curledAngleDeg && idx < clickRawThresholdDeg
        let middleExtended = mid >= extendedAngleDeg
        let middleCurled = mid < curledAngleDeg
        let ringCurled = ring < curledAngleDeg
        let pinkyCurled = pky < curledAngleDeg

        let kind: ClassifiedPose.Kind
        if indexExtended, middleCurled, ringCurled, pinkyCurled {
            kind = .pointing
        } else if indexExtended, middleExtended, ringCurled, pinkyCurled {
            kind = .scrolling
        } else if indexClickBent, middleCurled, ringCurled, pinkyCurled {
            kind = .indexBent
        } else {
            kind = .unknown
        }
        return ClassifiedPose(
            kind: kind,
            indexAngleDeg: idx,
            middleAngleDeg: mid,
            ringAngleDeg: ring,
            pinkyAngleDeg: pky
        )
    }

    /// Angle MCP→PIP→TIP, in degrees. 180 = fully straight, 0 = fully folded.
    public static func fingerAngleDeg(
        _ obs: HandObservation,
        mcp: JointName, pip: JointName, tip: JointName
    ) -> Double {
        guard let m = obs.points[mcp], let p = obs.points[pip], let t = obs.points[tip] else {
            return 0
        }
        let v1x = m.x - p.x
        let v1y = m.y - p.y
        let v2x = t.x - p.x
        let v2y = t.y - p.y
        let dot = v1x * v2x + v1y * v2y
        let mag1 = (v1x * v1x + v1y * v1y).squareRoot()
        let mag2 = (v2x * v2x + v2y * v2y).squareRoot()
        guard mag1 > 1e-9, mag2 > 1e-9 else { return 0 }
        let cosA = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosA) * 180.0 / .pi
    }
}
