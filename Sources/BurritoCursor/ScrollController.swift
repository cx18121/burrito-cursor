import CoreGraphics
import Foundation
import BurritoCursorCore

final class ScrollController {
    private let config: Config

    init(config: Config) {
        self.config = config
    }

    /// `deltaY` is normalized (frame fraction) per the recognizer. Convert to wheel lines.
    /// The 200x scale factor is empirical — re-tune during the bake test if scroll feels off.
    func scroll(deltaY: Double) {
        let lines = Int32((deltaY * 200).rounded())
        guard lines != 0 else { return }
        guard let evt = CGEvent(scrollWheelEvent2Source: nil,
                                units: .line,
                                wheelCount: 1,
                                wheel1: -lines, // invert: hand moves down → page scrolls down
                                wheel2: 0,
                                wheel3: 0) else {
            NSLog("BurritoCursor: failed to create scroll CGEvent")
            return
        }
        evt.post(tap: .cghidEventTap)
    }
}
