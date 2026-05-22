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

    /// Click latch fires when index curl ratio crosses this. Should be just
    /// above PoseClassifier.extendedCurlRatioMax — the moment the finger
    /// leaves the "fully extended" region.
    public var clickStartCurlRatio: Double
    /// Click confirms when index curl ratio has stayed above this for
    /// `debounceEntryFrames` frames in a row.
    public var clickConfirmCurlRatio: Double
    /// Click releases (and latch abandons) when index curl ratio drops below
    /// this — finger returned to extended.
    public var clickReleaseCurlRatio: Double

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
        clickStartCurlRatio: 1.15,
        clickConfirmCurlRatio: 1.30,
        clickReleaseCurlRatio: 1.10,
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
        if let v = store.object(forKey: "clickStartCurlRatio") as? Double, (1.0...3.0).contains(v) {
            c.clickStartCurlRatio = v
        }
        if let v = store.object(forKey: "clickConfirmCurlRatio") as? Double, (1.0...3.0).contains(v) {
            c.clickConfirmCurlRatio = v
        }
        if let v = store.object(forKey: "clickReleaseCurlRatio") as? Double, (1.0...3.0).contains(v) {
            c.clickReleaseCurlRatio = v
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
        // Invariant: release threshold <= start threshold <= confirm threshold
        if !(c.clickReleaseCurlRatio <= c.clickStartCurlRatio
             && c.clickStartCurlRatio <= c.clickConfirmCurlRatio) {
            c.clickStartCurlRatio = Config.defaults.clickStartCurlRatio
            c.clickConfirmCurlRatio = Config.defaults.clickConfirmCurlRatio
            c.clickReleaseCurlRatio = Config.defaults.clickReleaseCurlRatio
        }
        return c
    }
}
