import Foundation

public enum GestureState: Equatable {
    case idle
    case pointing(point: NormalizedPoint)              // cursor follows knuckle, no pinch yet
    case clicking(point: NormalizedPoint)              // pinch active — mouseDown held
    case scrolling(deltaY: Double, point: NormalizedPoint)
    /// Confidence below threshold — release any held click and wait for recovery.
    /// Equivalent to `.idle` for `InputCoordinator`, but distinct so the HUD/preview
    /// can surface "tracking lost" vs "no hand visible".
    case degraded
}
