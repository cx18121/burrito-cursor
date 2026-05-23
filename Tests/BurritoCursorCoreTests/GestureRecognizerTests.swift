import XCTest
@testable import BurritoCursorCore

final class GestureRecognizerTests: XCTestCase {
    private func pointingHand(at x: Double = 0.5, y: Double = 0.5, t: Double = 0, pinching: Bool = false) -> HandObservation {
        HandBuilder.makeHand(
            indexBendDeg: 180,
            middleBendDeg: 60,
            pinching: pinching,
            mcpAnchorX: x,
            mcpAnchorY: y,
            timestamp: t
        )
    }

    private func openPalmHand(at x: Double = 0.5, y: Double = 0.5, t: Double = 0) -> HandObservation {
        HandBuilder.makeHand(
            indexBendDeg: 180,
            middleBendDeg: 180,
            ringBendDeg: 180,
            pinkyBendDeg: 180,
            thumbBendDeg: 180,
            mcpAnchorX: x,
            mcpAnchorY: y,
            timestamp: t
        )
    }

    private func fistHand(t: Double = 0) -> HandObservation {
        HandBuilder.makeHand(
            indexBendDeg: 60,
            middleBendDeg: 60,
            ringBendDeg: 60,
            pinkyBendDeg: 60,
            thumbBendDeg: 60,
            timestamp: t
        )
    }

    // MARK: - Acquisition

    func testRequiresSustainedFramesToEnterPointing() {
        let r = GestureRecognizer(config: .defaults)
        XCTAssertEqual(r.step(pointingHand(t: 0)), .idle)
        guard case .pointing = r.step(pointingHand(t: 1.0/30)) else {
            return XCTFail("Expected .pointing after 2 frames")
        }
    }

    func testEmptyObservationReturnsIdle() {
        let r = GestureRecognizer(config: .defaults)
        XCTAssertEqual(r.step(HandObservation(timestampSec: 0, points: [:])), .idle)
    }

    // MARK: - Confidence

    func testLowConfidenceEntersDegraded() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        let low = HandBuilder.makeHand(indexBendDeg: 180, middleBendDeg: 60, timestamp: 3.0/30, confidence: 0.1)
        guard case .degraded = r.step(low) else {
            return XCTFail("Expected .degraded on low confidence")
        }
    }

    // MARK: - Hand-jump

    func testHandJumpResetsToIdle() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(at: 0.5, y: 0.5, t: Double(i)/30)) }
        XCTAssertEqual(r.step(pointingHand(at: 0.1, y: 0.1, t: 3.0/30)), .idle)
    }

    // MARK: - Pinch click

    func testPinchInPointingFiresClick() {
        let r = GestureRecognizer(config: .defaults)
        // Acquire pointing
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Pinch
        let clicked = r.step(pointingHand(t: 2.0/30, pinching: true))
        guard case .clicking = clicked else {
            return XCTFail("Expected .clicking on pinch, got \(clicked)")
        }
    }

    func testPinchReleaseReturnsToPointing() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        _ = r.step(pointingHand(t: 2.0/30, pinching: true))  // .clicking
        let released = r.step(pointingHand(t: 3.0/30, pinching: false))
        guard case .pointing = released else {
            return XCTFail("Expected .pointing on pinch release, got \(released)")
        }
    }

    func testFistDoesNotProduceClick() {
        let r = GestureRecognizer(config: .defaults)
        // Acquire pointing
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Switch to fist — pinching false (default), not pointing pose
        for i in 2..<8 {
            let state = r.step(fistHand(t: Double(i)/30))
            if case .clicking = state { XCTFail("Fist must not click") }
        }
    }

    func testPoseFlickerDuringPinchHoldsClick() {
        // Regression: when pose briefly classifies as something other than
        // .pointing (middle finger extends, say) while the pinch is still
        // active, we must stay in .clicking — not flicker to .pointing and
        // back, which would emit phantom mouseUp+mouseDown.
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        _ = r.step(pointingHand(t: 2.0/30, pinching: true))  // .clicking

        // Frame with index+middle extended (pinching still on): pose.kind
        // becomes .unknown (neither pointing nor openPalm) but pinch endures.
        let flicker = HandBuilder.makeHand(
            indexBendDeg: 180,
            middleBendDeg: 180,
            ringBendDeg: 60,
            pinkyBendDeg: 60,
            thumbBendDeg: 60,
            pinching: true,
            timestamp: 3.0/30
        )
        let state = r.step(flicker)
        guard case .clicking = state else {
            return XCTFail("Pose flicker during sustained pinch must NOT release click, got \(state)")
        }
    }

    // MARK: - Scroll

    func testEnterScrollFromPointing() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Switch to openPalm — needs `debounceEntryFrames` sustained frames.
        _ = r.step(openPalmHand(t: 2.0/30))
        let scrolled = r.step(openPalmHand(t: 3.0/30))
        guard case .scrolling = scrolled else {
            return XCTFail("Expected .scrolling after 2 frames of openPalm, got \(scrolled)")
        }
    }
}
