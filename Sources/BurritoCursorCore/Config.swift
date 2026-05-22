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
        if let v = store.object(forKey: "clickEnterAngleDeg") as? Double, (60.0...170.0).contains(v) {
            c.clickEnterAngleDeg = v
        }
        if let v = store.object(forKey: "clickExitAngleDeg") as? Double, (60.0...170.0).contains(v) {
            c.clickExitAngleDeg = v
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
        // Invariant: enter angle must be <= exit angle (hysteresis direction)
        if c.clickEnterAngleDeg > c.clickExitAngleDeg {
            c.clickEnterAngleDeg = Config.defaults.clickEnterAngleDeg
            c.clickExitAngleDeg = Config.defaults.clickExitAngleDeg
        }
        return c
    }
}
