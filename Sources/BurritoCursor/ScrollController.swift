import CoreGraphics
import Foundation
import BurritoCursorCore

final class ScrollController {
    private let config: Config

    init(config: Config) {
        self.config = config
    }

    /// `deltaY` is normalized (frame fraction) per the recognizer. Convert to pixel-level
    /// scroll for smooth feel (matches trackpad behavior). The 2000x scale factor is empirical.
    func scroll(deltaY: Double) {
        let pixels = Int32((deltaY * 2000).rounded())
        guard pixels != 0 else { return }
        guard let evt = CGEvent(scrollWheelEvent2Source: nil,
                                units: .pixel,
                                wheelCount: 1,
                                wheel1: -pixels, // invert: hand moves down → page scrolls down
                                wheel2: 0,
                                wheel3: 0) else {
            NSLog("BurritoCursor: failed to create scroll CGEvent")
            return
        }
        evt.post(tap: .cghidEventTap)
    }
}
