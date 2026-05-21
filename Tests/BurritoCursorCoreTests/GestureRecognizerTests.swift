import XCTest
@testable import BurritoCursorCore

final class GestureRecognizerTests: XCTestCase {
    func pointingHand(at x: Double = 0.5, y: Double = 0.5, t: Double = 0) -> HandObservation {
        HandBuilder.makeHand(
            indexBendDeg: 180,
            middleBendDeg: 60,
            mcpAnchorX: x,
            mcpAnchorY: y,
            timestamp: t
        )
    }

    func handWithIndexAngle(_ deg: Double, at x: Double = 0.5, y: Double = 0.5, t: Double = 0) -> HandObservation {
        HandBuilder.makeHand(
            indexBendDeg: max(0, min(180, deg)),
            middleBendDeg: 60,
            mcpAnchorX: x,
            mcpAnchorY: y,
            timestamp: t
        )
    }

    func scrollingHand(at x: Double = 0.5, y: Double = 0.5, t: Double = 0) -> HandObservation {
        HandBuilder.makeHand(
            indexBendDeg: 180,
            middleBendDeg: 180,
            ringBendDeg: 60,
            pinkyBendDeg: 60,
            mcpAnchorX: x,
            mcpAnchorY: y,
            timestamp: t
        )
    }

    // MARK: - Acquisition

    func testRequiresThreeFramesToEnterPointing() {
        let r = GestureRecognizer(config: .defaults)
        XCTAssertEqual(r.step(pointingHand(t: 0)), .idle)
        XCTAssertEqual(r.step(pointingHand(t: 1.0/30)), .idle)
        guard case .pointing = r.step(pointingHand(t: 2.0/30)) else {
            return XCTFail("Expected .pointing after 3 frames")
        }
    }

    func testEmptyObservationReturnsIdle() {
        let r = GestureRecognizer(config: .defaults)
        let empty = HandObservation(timestampSec: 0, points: [:])
        XCTAssertEqual(r.step(empty), .idle)
    }

    // MARK: - Confidence

    func testLowConfidenceEntersDegraded() {
        let r = GestureRecognizer(config: .defaults)
        // Acquire pointing
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        let lowConf = HandBuilder.makeHand(
            indexBendDeg: 180, middleBendDeg: 60,
            timestamp: 3.0/30, confidence: 0.1
        )
        guard case .degraded = r.step(lowConf) else {
            return XCTFail("Expected .degraded on low confidence")
        }
    }

    func testDegradedRequiresReacquisition() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        let lowConf = HandBuilder.makeHand(
            indexBendDeg: 180, middleBendDeg: 60,
            timestamp: 3.0/30, confidence: 0.1
        )
        _ = r.step(lowConf)
        // Now recover with high confidence — single frame should NOT promote to pointing
        let state = r.step(pointingHand(t: 4.0/30))
        XCTAssertEqual(state, .idle, "Single recovered frame should not promote — re-acquisition required")
        _ = r.step(pointingHand(t: 5.0/30))
        guard case .pointing = r.step(pointingHand(t: 6.0/30)) else {
            return XCTFail("Expected .pointing after 3 recovered frames")
        }
    }

    // MARK: - Hand-jump

    func testHandJumpResetsToIdle() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(at: 0.5, y: 0.5, t: Double(i)/30)) }
        let jumped = r.step(pointingHand(at: 0.1, y: 0.1, t: 3.0/30))
        XCTAssertEqual(jumped, .idle, "Hand-jump > 25% frame width should reset to idle")
    }

    // MARK: - Click

    func testClickLatchAndConfirm() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Angle 150 — below exit (155) but above enter (140): latch
        let latched = r.step(handWithIndexAngle(150, t: 3.0/30))
        guard case .clickLatched = latched else {
            return XCTFail("Expected .clickLatched at 150°, got \(latched)")
        }
        // Three frames at 130 (below enter 140): confirm click
        _ = r.step(handWithIndexAngle(130, t: 4.0/30))
        _ = r.step(handWithIndexAngle(130, t: 5.0/30))
        let clicked = r.step(handWithIndexAngle(130, t: 6.0/30))
        guard case .clicking = clicked else {
            return XCTFail("Expected .clicking after sustained bend, got \(clicked)")
        }
    }

    func testClickReleaseImmediateOnStraighten() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        _ = r.step(handWithIndexAngle(150, t: 3.0/30))
        _ = r.step(handWithIndexAngle(130, t: 4.0/30))
        _ = r.step(handWithIndexAngle(130, t: 5.0/30))
        _ = r.step(handWithIndexAngle(130, t: 6.0/30))
        // Single frame above exit threshold → immediate release
        let released = r.step(handWithIndexAngle(170, t: 7.0/30))
        guard case .pointing = released else {
            return XCTFail("Expected immediate .pointing on release, got \(released)")
        }
    }

    func testClickLatchAbandonOnStraighten() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        _ = r.step(handWithIndexAngle(150, t: 3.0/30)) // latched
        // User straightens before confirming
        let abandoned = r.step(handWithIndexAngle(170, t: 4.0/30))
        guard case .pointing = abandoned else {
            return XCTFail("Expected .pointing after latch abandoned, got \(abandoned)")
        }
    }

    // MARK: - Scroll

    func testEnterScrollFromPointing() {
        let r = GestureRecognizer(config: .defaults)
        // Acquire pointing
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Switch to scrolling pose for 3 frames
        _ = r.step(scrollingHand(t: 3.0/30))
        _ = r.step(scrollingHand(t: 4.0/30))
        let scrolled = r.step(scrollingHand(t: 5.0/30))
        guard case .scrolling = scrolled else {
            return XCTFail("Expected .scrolling, got \(scrolled)")
        }
    }
}
