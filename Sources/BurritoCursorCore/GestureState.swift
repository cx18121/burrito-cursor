import Foundation

public enum GestureState: Equatable {
    case idle
    case pointing(point: NormalizedPoint)
    case clickLatched(point: NormalizedPoint)
    case clicking(point: NormalizedPoint)
    case scrolling(deltaY: Double, point: NormalizedPoint)
    case degraded(previous: PreviousNonDegraded)

    public enum PreviousNonDegraded: Equatable {
        case idle
        case pointing(point: NormalizedPoint)
        case clickLatched(point: NormalizedPoint)
        case clicking(point: NormalizedPoint)
        case scrolling(point: NormalizedPoint)
    }
}
