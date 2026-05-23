import Foundation

/// One frame's worth of pipeline output, bundled for display consumers
/// (Debug HUD, preview window, future overlays).
///
/// Built once per detector callback in `PipelineRunner`; consumers receive it
/// instead of accumulating positional parameters and re-running classification.
public struct PipelineSnapshot {
    public let state: GestureState
    /// Pose classification from the recognizer's most recent step. `nil` when
    /// no hand was visible or confidence was below the degraded threshold.
    public let pose: ClassifiedPose?
    /// Raw landmark observation (or `nil` when no hand was visible). Carried
    /// so the preview overlay can render landmarks without a separate stream.
    public let observation: HandObservation?
    public let frameRateHz: Double
    public let visionLatencyMs: Double

    public init(
        state: GestureState,
        pose: ClassifiedPose?,
        observation: HandObservation?,
        frameRateHz: Double,
        visionLatencyMs: Double
    ) {
        self.state = state
        self.pose = pose
        self.observation = observation
        self.frameRateHz = frameRateHz
        self.visionLatencyMs = visionLatencyMs
    }

    public var minConfidence: Double { observation?.minConfidence ?? 0.0 }
    public var landmarkCount: Int { observation?.points.count ?? 0 }
}
