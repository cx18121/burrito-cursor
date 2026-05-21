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

public struct HandObservation: Codable, Equatable {
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
