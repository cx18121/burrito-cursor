import XCTest
@testable import BurritoCursorCore

final class ConfigTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let cfg = Config.defaults
        XCTAssertEqual(cfg.sensitivity, 1.0)
        XCTAssertEqual(cfg.deadzoneNormalized, 0.005)
        XCTAssertEqual(cfg.debounceEntryFrames, 2)
        XCTAssertEqual(cfg.debounceExitFrames, 1)
        XCTAssertEqual(cfg.pinchStartDistance, 0.18)
        XCTAssertEqual(cfg.pinchEndDistance, 0.30)
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
        XCTAssertEqual(cfg.pinchStartDistance, 0.18, "Untouched keys fall back to defaults")
    }

    func testInvariantsRejectInvalidValues() {
        let store = InMemoryKVStore(["sensitivity": -1.0])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.sensitivity, 1.0)
    }

    func testRangeBoundariesRejected() {
        let store = InMemoryKVStore([
            "sensitivity": 100.0,
            "debounceEntryFrames": 1000,
            "pinchStartDistance": 10.0,
            "degradedConfidenceThreshold": 1.5,
            "oneEuroBeta": -0.1,
        ])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.sensitivity, 1.0)
        XCTAssertEqual(cfg.debounceEntryFrames, 2)
        XCTAssertEqual(cfg.pinchStartDistance, 0.18)
        XCTAssertEqual(cfg.degradedConfidenceThreshold, 0.3)
        XCTAssertEqual(cfg.oneEuroBeta, 0.007)
    }

    func testPinchHysteresisInvariant() {
        // start >= end is invalid (no hysteresis) → fall back to defaults
        let store = InMemoryKVStore([
            "pinchStartDistance": 0.4,
            "pinchEndDistance": 0.2,
        ])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.pinchStartDistance, 0.18)
        XCTAssertEqual(cfg.pinchEndDistance, 0.30)
    }
}

final class InMemoryKVStore: KVStore {
    private var dict: [String: Any]
    init(_ dict: [String: Any] = [:]) { self.dict = dict }
    func object(forKey key: String) -> Any? { dict[key] }
}
