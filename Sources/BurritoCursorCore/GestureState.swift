import Foundation

public enum GestureState: Equatable {
    case idle
    case pointing(point: NormalizedPoint)              // cursor follows knuckle, no pinch yet
    case clicking(point: NormalizedPoint)              // pinch active — mouseDown held
    case scrolling(deltaY: Double, point: NormalizedPoint)
    case degraded(previous: PreviousNonDegraded)

    public enum PreviousNonDegraded: Equatable {
        case idle
        case pointing(point: NormalizedPoint)
        case clicking(point: NormalizedPoint)
        case scrolling(point: NormalizedPoint)
    }
}
