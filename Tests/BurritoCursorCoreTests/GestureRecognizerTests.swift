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

    func testRequiresSustainedFramesToEnterPointing() {
        // Default debounce is 2 frames — must remain at idle on frame 1, promote on frame 2.
        let r = GestureRecognizer(config: .defaults)
        XCTAssertEqual(r.step(pointingHand(t: 0)), .idle)
        guard case .pointing = r.step(pointingHand(t: 1.0/30)) else {
            return XCTFail("Expected .pointing after 2 frames")
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
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // bendDeg=110 → curl_ratio ≈ 1.22, in click-start window → latch
        let latched = r.step(handWithIndexAngle(110, t: 2.0/30))
        guard case .clickLatched = latched else {
            return XCTFail("Expected .clickLatched, got \(latched)")
        }
        // bendDeg=90 → curl_ratio ≈ 1.41, above confirm threshold. Two
        // sustained frames at confirm depth → .clicking.
        _ = r.step(handWithIndexAngle(90, t: 3.0/30))
        let clicked = r.step(handWithIndexAngle(90, t: 4.0/30))
        guard case .clicking = clicked else {
            return XCTFail("Expected .clicking after sustained bend, got \(clicked)")
        }
    }

    func testClickReleaseImmediateOnStraighten() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        _ = r.step(handWithIndexAngle(110, t: 2.0/30))  // latch
        _ = r.step(handWithIndexAngle(90, t: 3.0/30))
        _ = r.step(handWithIndexAngle(90, t: 4.0/30))   // → clicking
        // Index straightens (curl_ratio ≈ 1.0) → immediate release
        let released = r.step(handWithIndexAngle(180, t: 5.0/30))
        guard case .pointing = released else {
            return XCTFail("Expected immediate .pointing on release, got \(released)")
        }
    }

    func testClickLatchAbandonOnStraighten() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<2 { _ = r.step(pointingHand(t: Double(i)/30)) }
        _ = r.step(handWithIndexAngle(110, t: 2.0/30))  // latched
        // User straightens before confirming
        let abandoned = r.step(handWithIndexAngle(180, t: 3.0/30))
        guard case .pointing = abandoned else {
            return XCTFail("Expected .pointing after latch abandoned, got \(abandoned)")
        }
    }

    // MARK: - Phantom-click prevention

    func testClosedFistDoesNotProduceClick() {
        let r = GestureRecognizer(config: .defaults)
        // Acquire pointing first
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Suddenly all fingers curl to a fist (60° on every finger)
        for i in 3..<8 {
            let fist = HandBuilder.makeHand(
                indexBendDeg: 60, middleBendDeg: 60, ringBendDeg: 60, pinkyBendDeg: 60,
                timestamp: Double(i)/30
            )
            let state = r.step(fist)
            // Must never reach .clicking, and the cursor-locking .clickLatched is also unwanted
            // because it would freeze the cursor on an accidental fist. Idle or pointing is OK.
            if case .clicking = state { XCTFail("Fist must not click") }
            if case .clickLatched = state { XCTFail("Fist must not latch") }
        }
    }

    /// Targets the original phantom-click bug directly: index bent into the click
    /// window (130° → satisfies the old "idx < clickExitAngleDeg" condition) but
    /// the other fingers are NOT curled (160° each). Under the original buggy code
    /// this would latch and then confirm as a click. The fix gates on others-curled,
    /// so this must stay in `.pointing` (well — actually `.idle`, since the hand
    /// pose no longer matches `.pointing`).
    func testIndexBentWithOthersExtendedDoesNotLatch() {
        let r = GestureRecognizer(config: .defaults)
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Index bent to 130° but middle/ring/pinky still extended — looks like
        // a goofy splayed claw, not a click bend.
        for i in 3..<8 {
            let claw = HandBuilder.makeHand(
                indexBendDeg: 130,
                middleBendDeg: 165, ringBendDeg: 165, pinkyBendDeg: 165,
                timestamp: Double(i)/30
            )
            let state = r.step(claw)
            if case .clickLatched = state { XCTFail("Must not latch when other fingers aren't curled") }
            if case .clicking = state { XCTFail("Must not click when other fingers aren't curled") }
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
