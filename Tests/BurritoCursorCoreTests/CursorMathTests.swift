import XCTest
@testable import BurritoCursorCore

final class CursorMathTests: XCTestCase {
    private let screen: (width: Double, height: Double) = (1920, 1080)

    private func make() -> (OneEuroFilter, OneEuroFilter) {
        (OneEuroFilter(minCutoff: 1.0, beta: 0.007),
         OneEuroFilter(minCutoff: 1.0, beta: 0.007))
    }

    private func pt(_ x: Double, _ y: Double) -> NormalizedPoint {
        NormalizedPoint(x: x, y: y, confidence: 1.0)
    }

    func testDeadzoneZerosTinyMotion() {
        var (fx, fy) = make()
        let r = CursorMath.computeDelta(
            current: pt(0.500, 0.500),
            previous: pt(0.5005, 0.5005), // smaller than deadzone (0.005)
            screenSize: screen,
            config: .defaults,
            timestamp: 0,
            filterX: &fx, filterY: &fy
        )
        XCTAssertEqual(r.dx, 0)
        XCTAssertEqual(r.dy, 0)
    }

    func testYAxisInverted() {
        var (fx, fy) = make()
        // Hand moves UP in image space (y increases — Vision is bottom-left origin)
        let r = CursorMath.computeDelta(
            current: pt(0.5, 0.7),
            previous: pt(0.5, 0.5),
            screenSize: screen,
            config: .defaults,
            timestamp: 0,
            filterX: &fx, filterY: &fy
        )
        // Cursor coordinate is top-left origin → moving up in image = decreasing cursor y
        XCTAssertLessThan(r.dy, 0)
    }

    func testSensitivityScalesProportionally() {
        var (fx1, fy1) = make()
        var (fx2, fy2) = make()
        var cfg = Config.defaults
        let r1 = CursorMath.computeDelta(
            current: pt(0.6, 0.5),
            previous: pt(0.5, 0.5),
            screenSize: screen,
            config: cfg,
            timestamp: 0,
            filterX: &fx1, filterY: &fy1
        )
        cfg.sensitivity = 2.0
        let r2 = CursorMath.computeDelta(
            current: pt(0.6, 0.5),
            previous: pt(0.5, 0.5),
            screenSize: screen,
            config: cfg,
            timestamp: 0,
            filterX: &fx2, filterY: &fy2
        )
        XCTAssertEqual(r2.dx, r1.dx * 2.0, accuracy: 1e-6)
    }

    func testReferenceSweepMapping() {
        // A 20cm arm sweep across normalized frame (0.0 → 1.0 of the reference fraction)
        // should produce a full-screen-width cursor delta at sensitivity 1.0.
        var (fx, fy) = make()
        let r = CursorMath.computeDelta(
            current: pt(0.7, 0.5),
            previous: pt(0.5, 0.5), // dx = 0.2 = full reference sweep
            screenSize: screen,
            config: .defaults,
            timestamp: 0,
            filterX: &fx, filterY: &fy,
            referenceArmSweepFraction: 0.2
        )
        // First sample through OneEuroFilter passes the value through identity,
        // so raw scaled value is screen width.
        XCTAssertEqual(r.dx, screen.width, accuracy: 1e-6)
    }
}
