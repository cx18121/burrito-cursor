import Foundation

public protocol KVStore {
    func object(forKey key: String) -> Any?
}

extension UserDefaults: KVStore {}

public struct Config: Equatable {
    public var sensitivity: Double
    public var deadzoneNormalized: Double
    public var debounceEntryFrames: Int
    public var debounceExitFrames: Int

    /// Pinch detection — Apple Vision Pro "select" gesture.
    /// `pinchStart` < `pinchEnd` enforces hysteresis to avoid flicker at the boundary.
    /// Values are |thumbTip − indexTip| normalized by palm scale.
    public var pinchStartDistance: Double
    public var pinchEndDistance: Double

    public var degradedConfidenceThreshold: Double
    public var handJumpRejectionFraction: Double
    public var scrollSensitivity: Double
    public var oneEuroBeta: Double
    public var oneEuroMinCutoff: Double

    public static let defaults = Config(
        sensitivity: 1.0,
        deadzoneNormalized: 0.005,
        debounceEntryFrames: 2,
        debounceExitFrames: 1,
        pinchStartDistance: 0.18,
        pinchEndDistance: 0.30,
        degradedConfidenceThreshold: 0.3,
        handJumpRejectionFraction: 0.25,
        scrollSensitivity: 1.0,
        oneEuroBeta: 0.007,
        oneEuroMinCutoff: 1.0
    )

    public static func load(from store: KVStore) -> Config {
        var c = Config.defaults
        if let v = store.object(forKey: "sensitivity") as? Double, (0.05...20.0).contains(v) {
            c.sensitivity = v
        }
        if let v = store.object(forKey: "deadzoneNormalized") as? Double, (0...0.2).contains(v) {
            c.deadzoneNormalized = v
        }
        if let v = store.object(forKey: "debounceEntryFrames") as? Int, (1...30).contains(v) {
            c.debounceEntryFrames = v
        }
        if let v = store.object(forKey: "debounceExitFrames") as? Int, (1...30).contains(v) {
            c.debounceExitFrames = v
        }
        if let v = store.object(forKey: "pinchStartDistance") as? Double, (0.01...1.0).contains(v) {
            c.pinchStartDistance = v
        }
        if let v = store.object(forKey: "pinchEndDistance") as? Double, (0.01...1.0).contains(v) {
            c.pinchEndDistance = v
        }
        if let v = store.object(forKey: "degradedConfidenceThreshold") as? Double, (0.0...1.0).contains(v) {
            c.degradedConfidenceThreshold = v
        }
        if let v = store.object(forKey: "handJumpRejectionFraction") as? Double, (0.01...1.0).contains(v) {
            c.handJumpRejectionFraction = v
        }
        if let v = store.object(forKey: "scrollSensitivity") as? Double, (0.05...20.0).contains(v) {
            c.scrollSensitivity = v
        }
        if let v = store.object(forKey: "oneEuroBeta") as? Double, (0.0...10.0).contains(v) {
            c.oneEuroBeta = v
        }
        if let v = store.object(forKey: "oneEuroMinCutoff") as? Double, (0.01...100.0).contains(v) {
            c.oneEuroMinCutoff = v
        }
        // Invariant: pinch start must be strictly less than pinch end (hysteresis).
        if c.pinchStartDistance >= c.pinchEndDistance {
            c.pinchStartDistance = Config.defaults.pinchStartDistance
            c.pinchEndDistance = Config.defaults.pinchEndDistance
        }
        return c
    }
}
