import Foundation

/// Pure cursor-delta math, extracted from `CursorController` for unit testing.
/// All inputs are deterministic; no side effects, no time-of-day calls.
public enum CursorMath {
    public struct Result {
        public var dx: Double
        public var dy: Double
    }

    /// Compute filtered cursor delta in screen pixels.
    /// - `current`/`previous` are normalized MCP positions; y origin is bottom-left
    ///   (Vision convention) so we invert y to map to top-left CGEvent cursor coords.
    /// - `referenceArmSweepFraction` (default 0.2) is the fraction of normalized
    ///   frame width that maps to a full screen sweep at sensitivity 1.0.
    public static func computeDelta(
        current: NormalizedPoint,
        previous: NormalizedPoint,
        screenSize: (width: Double, height: Double),
        config: Config,
        timestamp: Double,
        filterX: inout OneEuroFilter,
        filterY: inout OneEuroFilter,
        referenceArmSweepFraction: Double = 0.2
    ) -> Result {
        var dx = current.x - previous.x
        var dy = -(current.y - previous.y) // Vision bottom-left → cursor top-left

        if abs(dx) < config.deadzoneNormalized { dx = 0 }
        if abs(dy) < config.deadzoneNormalized { dy = 0 }

        let scaleX = screenSize.width * config.sensitivity / referenceArmSweepFraction
        let scaleY = screenSize.height * config.sensitivity / referenceArmSweepFraction

        let sx = filterX.filter(dx * scaleX, timestampSec: timestamp)
        let sy = filterY.filter(dy * scaleY, timestampSec: timestamp)
        return Result(dx: sx, dy: sy)
    }
}
