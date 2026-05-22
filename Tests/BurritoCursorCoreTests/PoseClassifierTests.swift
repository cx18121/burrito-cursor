import XCTest
@testable import BurritoCursorCore

final class PoseClassifierTests: XCTestCase {
    func testPointingPose() {
        // Index extended (180°), middle/ring/pinky bent. Should classify as pointing.
        let hand = HandBuilder.makeHand(indexBendDeg: 180, middleBendDeg: 60)
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .pointing)
        XCTAssertEqual(pose.indexAngleDeg, 180, accuracy: 5)
    }

    func testOpenPalmPose() {
        // All five fingers extended.
        let hand = HandBuilder.makeHand(
            indexBendDeg: 180,
            middleBendDeg: 180,
            ringBendDeg: 180,
            pinkyBendDeg: 180,
            thumbBendDeg: 180
        )
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .openPalm)
    }

    func testFistIsUnknown() {
        // Every finger curled including thumb — neither pointing nor openPalm.
        let hand = HandBuilder.makeHand(
            indexBendDeg: 60,
            middleBendDeg: 60,
            ringBendDeg: 60,
            pinkyBendDeg: 60,
            thumbBendDeg: 60
        )
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .unknown)
    }

    func testPinchDistance() {
        let open = HandBuilder.makeHand(pinching: false)
        let closed = HandBuilder.makeHand(pinching: true)
        let openPose = PoseClassifier.classify(open)
        let closedPose = PoseClassifier.classify(closed)
        XCTAssertGreaterThan(openPose.pinchDistance, 0.30, "Unpinched hand should be well above pinch threshold")
        XCTAssertLessThan(closedPose.pinchDistance, 0.05, "Pinched hand should report ~zero distance")
    }

    func testFingerAngleCalculation() {
        let straight = HandBuilder.makeHand(indexBendDeg: 180)
        XCTAssertEqual(
            PoseClassifier.fingerAngleDeg(straight, mcp: .indexMCP, pip: .indexPIP, tip: .indexTip),
            180, accuracy: 0.5
        )
        let bent = HandBuilder.makeHand(indexBendDeg: 90)
        XCTAssertEqual(
            PoseClassifier.fingerAngleDeg(bent, mcp: .indexMCP, pip: .indexPIP, tip: .indexTip),
            90, accuracy: 0.5
        )
    }
}
