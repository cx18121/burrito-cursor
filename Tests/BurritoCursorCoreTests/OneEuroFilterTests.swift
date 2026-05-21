import XCTest
@testable import BurritoCursorCore

final class OneEuroFilterTests: XCTestCase {
    func testFirstSampleReturnsItself() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007)
        let y = f.filter(5.0, timestampSec: 0.0)
        XCTAssertEqual(y, 5.0, accuracy: 1e-9)
    }

    func testConstantSignalConverges() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007)
        var last = 0.0
        for i in 0..<100 {
            last = f.filter(10.0, timestampSec: Double(i) * 1.0 / 30.0)
        }
        XCTAssertEqual(last, 10.0, accuracy: 1e-3)
    }

    func testSlowMotionGetsSmoothed() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.0)
        var ys: [Double] = []
        for i in 0..<10 {
            let sample = i.isMultiple(of: 2) ? 0.0 : 1.0
            ys.append(f.filter(sample, timestampSec: Double(i) * 1.0 / 30.0))
        }
        XCTAssertLessThan(ys.last!, 1.0, "No sample should reach full amplitude instantly")
        XCTAssertGreaterThan(ys.last!, 0.0)
    }

    func testFastMotionPassesThrough() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 1.0)
        _ = f.filter(0.0, timestampSec: 0.0)
        let y = f.filter(100.0, timestampSec: 0.01)
        XCTAssertGreaterThan(y, 50.0, "Fast motion with high beta should pass through")
    }
}
