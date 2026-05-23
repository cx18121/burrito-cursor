import Foundation

/// Per-finger signals computed each frame. The classifier combines these into
/// `isExtended` decisions; the recognizer reads pose `kind` and `pinchDistance`.
public struct FingerSignals: Equatable {
    /// 2D angle at the PIP joint (MCP → PIP → TIP). 180° = straight. Display-only.
    public let angleDeg: Double
    /// Sum of segment lengths / straight-line distance. 1.0 = straight, ∞ = folded.
    /// Primary classification signal — orientation-invariant in 2D.
    public let curlRatio: Double
    /// |TIP − MCP| / palmScale. Secondary signal, HUD display.
    public let chordNormalized: Double
}

public struct ClassifiedPose: Equatable {
    public enum Kind: Equatable {
        case pointing   // index extended, middle/ring/pinky NOT extended → cursor mode
        case openPalm   // all 5 fingers extended (incl. thumb) → scroll mode
        case unknown
    }
    public let kind: Kind
    public let thumb: FingerSignals
    public let index: FingerSignals
    public let middle: FingerSignals
    public let ring: FingerSignals
    public let pinky: FingerSignals

    /// Thumb-tip to index-tip distance normalized by palm scale. Drives click via
    /// pinch — sub-threshold = pinching = click. Independent of pose `kind`, but
    /// only meaningful while in `.pointing`.
    public let pinchDistance: Double

    // Convenience accessors for HUD / preview display.
    public var indexAngleDeg: Double { index.angleDeg }
    public var middleAngleDeg: Double { middle.angleDeg }
    public var ringAngleDeg: Double { ring.angleDeg }
    public var pinkyAngleDeg: Double { pinky.angleDeg }
}

public enum PoseClassifier {
    /// curlRatio below this → finger is straight (extended).
    public static let extendedCurlRatioMax = 1.10
    /// curlRatio above this → finger is folded (curled). Used by isCurled().
    public static let curledCurlRatioMin = 1.60

    public static func classify(_ obs: HandObservation) -> ClassifiedPose {
        let palmScale = computePalmScale(obs)
        let thumb = signals(mcp: .thumbCMC, pip: .thumbMP, dip: .thumbIP, tip: .thumbTip, obs: obs, palmScale: palmScale)
        let index = signals(mcp: .indexMCP,  pip: .indexPIP,  dip: .indexDIP,  tip: .indexTip,  obs: obs, palmScale: palmScale)
        let middle = signals(mcp: .middleMCP, pip: .middlePIP, dip: .middleDIP, tip: .middleTip, obs: obs, palmScale: palmScale)
        let ring = signals(mcp: .ringMCP,   pip: .ringPIP,   dip: .ringDIP,   tip: .ringTip,   obs: obs, palmScale: palmScale)
        let pinky = signals(mcp: .pinkyMCP,  pip: .pinkyPIP,  dip: .pinkyDIP,  tip: .pinkyTip,  obs: obs, palmScale: palmScale)

        let pinchDistance = pinchDistanceNormalized(obs: obs, palmScale: palmScale)

        let indexExt = isExtended(index)
        let middleExt = isExtended(middle)
        let ringExt = isExtended(ring)
        let pinkyExt = isExtended(pinky)
        let thumbExt = isExtended(thumb)

        let kind: ClassifiedPose.Kind
        if thumbExt, indexExt, middleExt, ringExt, pinkyExt {
            // All five extended → open palm → scroll mode.
            kind = .openPalm
        } else if indexExt, !middleExt, !ringExt, !pinkyExt {
            // Only the index is clearly extended; other fingers can be curled
            // OR partially bent — anything except "fully extended" is acceptable.
            // This is much more forgiving than the old "all others must be curled"
            // requirement.
            kind = .pointing
        } else {
            kind = .unknown
        }
        return ClassifiedPose(
            kind: kind,
            thumb: thumb, index: index, middle: middle, ring: ring, pinky: pinky,
            pinchDistance: pinchDistance
        )
    }

    public static func isExtended(_ s: FingerSignals) -> Bool {
        s.curlRatio < extendedCurlRatioMax
    }
    public static func isCurled(_ s: FingerSignals) -> Bool {
        s.curlRatio > curledCurlRatioMin
    }

    // MARK: - Pinch

    /// Returns `|thumbTip − indexTip| / palmScale`. ~0.4 for a relaxed hand,
    /// near 0 when pinched (Apple Vision Pro "select" gesture).
    public static func pinchDistanceNormalized(obs: HandObservation, palmScale: Double) -> Double {
        guard let thumbTip = obs.points[.thumbTip],
              let indexTip = obs.points[.indexTip] else { return .infinity }
        let d = distance(thumbTip, indexTip)
        return palmScale > 1e-6 ? d / palmScale : .infinity
    }

    // MARK: - Geometry

    private static func computePalmScale(_ obs: HandObservation) -> Double {
        if let w = obs.points[.wrist], let m = obs.points[.middleMCP] {
            let d = distance(w, m)
            if d > 1e-3 { return d }
        }
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
