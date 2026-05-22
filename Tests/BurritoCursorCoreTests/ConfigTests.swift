import XCTest
@testable import BurritoCursorCore

final class ConfigTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let cfg = Config.defaults
        XCTAssertEqual(cfg.sensitivity, 1.0)
        XCTAssertEqual(cfg.deadzoneNormalized, 0.005)
        XCTAssertEqual(cfg.debounceEntryFrames, 2)
        XCTAssertEqual(cfg.debounceExitFrames, 1)
        XCTAssertEqual(cfg.clickEnterAngleDeg, 145.0)
        XCTAssertEqual(cfg.clickExitAngleDeg, 155.0)
        XCTAssertEqual(cfg.degradedConfidenceThreshold, 0.3)
        XCTAssertEqual(cfg.handJumpRejectionFraction, 0.25)
        XCTAssertEqual(cfg.scrollSensitivity, 1.0)
        XCTAssertEqual(cfg.oneEuroBeta, 0.007)
        XCTAssertEqual(cfg.oneEuroMinCutoff, 1.0)
    }

    func testLoadFromInMemoryStore() {
        let store = InMemoryKVStore([
            "sensitivity": 2.5,
            "deadzoneNormalized": 0.01,
        ])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.sensitivity, 2.5)
        XCTAssertEqual(cfg.deadzoneNormalized, 0.01)
        XCTAssertEqual(cfg.clickEnterAngleDeg, 145.0, "Untouched keys fall back to defaults")
    }

    func testInvariantsRejectInvalidValues() {
        let store = InMemoryKVStore(["sensitivity": -1.0])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.sensitivity, 1.0, "Negative sensitivity must fall back to default")
    }

    func testRangeBoundariesRejected() {
        let store = InMemoryKVStore([
            "sensitivity": 100.0,                  // > 20 max
            "debounceEntryFrames": 1000,           // > 30 max
            "clickEnterAngleDeg": 200.0,           // > 170 max
            "degradedConfidenceThreshold": 1.5,    // > 1 max
            "oneEuroBeta": -0.1,                   // < 0 min
        ])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.sensitivity, 1.0)
        XCTAssertEqual(cfg.debounceEntryFrames, 2)
        XCTAssertEqual(cfg.clickEnterAngleDeg, 145.0)
        XCTAssertEqual(cfg.degradedConfidenceThreshold, 0.3)
        XCTAssertEqual(cfg.oneEuroBeta, 0.007)
    }

    func testEnterMustBeLessThanOrEqualToExit() {
        // Backwards values fall back to default pair, not partially-corrupted state
        let store = InMemoryKVStore([
            "clickEnterAngleDeg": 160.0,
            "clickExitAngleDeg": 130.0,
        ])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.clickEnterAngleDeg, 145.0)
        XCTAssertEqual(cfg.clickExitAngleDeg, 155.0)
    }
}

final class InMemoryKVStore: KVStore {
    private var dict: [String: Any]
    init(_ dict: [String: Any] = [:]) { self.dict = dict }
    func object(forKey key: String) -> Any? { dict[key] }
}
