import Foundation

public enum JointName: String, Codable, CaseIterable, Hashable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case pinkyMCP, pinkyPIP, pinkyDIP, pinkyTip
}

public struct NormalizedPoint: Codable, Equatable {
    /// Image-space coords. x is pre-mirrored to match screen orientation (right-in-frame = right-on-screen).
    /// y origin is bottom-left (Vision convention). Range [0,1].
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public struct HandObservation: Equatable {
    public var timestampSec: Double
    public var points: [JointName: NormalizedPoint]

    public init(timestampSec: Double, points: [JointName: NormalizedPoint]) {
        self.timestampSec = timestampSec
        self.points = points
    }

    public var minConfidence: Double {
        points.values.map(\.confidence).min() ?? 0.0
    }
}

// Custom Codable so `points` serializes as a JSON object keyed by JointName.rawValue
// (otherwise Swift uses an alternating-array form for dictionaries with enum keys).
extension HandObservation: Codable {
    private enum CodingKeys: String, CodingKey {
        case timestampSec, points
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.timestampSec = try c.decode(Double.self, forKey: .timestampSec)
        let raw = try c.decode([String: NormalizedPoint].self, forKey: .points)
        var pts: [JointName: NormalizedPoint] = [:]
        for (k, v) in raw {
            if let joint = JointName(rawValue: k) { pts[joint] = v }
        }
        self.points = pts
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(timestampSec, forKey: .timestampSec)
        var raw: [String: NormalizedPoint] = [:]
        for (k, v) in points { raw[k.rawValue] = v }
        try c.encode(raw, forKey: .points)
    }
}
