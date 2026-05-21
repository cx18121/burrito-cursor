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
    public var clickEnterAngleDeg: Double
    public var clickExitAngleDeg: Double
    public var degradedConfidenceThreshold: Double
    public var handJumpRejectionFraction: Double
    public var scrollSensitivity: Double
    public var oneEuroBeta: Double
    public var oneEuroMinCutoff: Double

    public static let defaults = Config(
        sensitivity: 1.0,
        deadzoneNormalized: 0.005,
        debounceEntryFrames: 3,
        debounceExitFrames: 1,
        clickEnterAngleDeg: 140.0,
        clickExitAngleDeg: 155.0,
        degradedConfidenceThreshold: 0.3,
        handJumpRejectionFraction: 0.25,
        scrollSensitivity: 1.0,
        oneEuroBeta: 0.007,
        oneEuroMinCutoff: 1.0
    )

    public static func load(from store: KVStore) -> Config {
        var c = Config.defaults
        if let v = store.object(forKey: "sensitivity") as? Double, v > 0 { c.sensitivity = v }
        if let v = store.object(forKey: "deadzoneNormalized") as? Double, v >= 0 { c.deadzoneNormalized = v }
        if let v = store.object(forKey: "debounceEntryFrames") as? Int, v >= 1 { c.debounceEntryFrames = v }
        if let v = store.object(forKey: "debounceExitFrames") as? Int, v >= 1 { c.debounceExitFrames = v }
        if let v = store.object(forKey: "clickEnterAngleDeg") as? Double { c.clickEnterAngleDeg = v }
        if let v = store.object(forKey: "clickExitAngleDeg") as? Double { c.clickExitAngleDeg = v }
        if let v = store.object(forKey: "degradedConfidenceThreshold") as? Double { c.degradedConfidenceThreshold = v }
        if let v = store.object(forKey: "handJumpRejectionFraction") as? Double, v > 0 { c.handJumpRejectionFraction = v }
        if let v = store.object(forKey: "scrollSensitivity") as? Double, v > 0 { c.scrollSensitivity = v }
        if let v = store.object(forKey: "oneEuroBeta") as? Double { c.oneEuroBeta = v }
        if let v = store.object(forKey: "oneEuroMinCutoff") as? Double { c.oneEuroMinCutoff = v }
        return c
    }
}
