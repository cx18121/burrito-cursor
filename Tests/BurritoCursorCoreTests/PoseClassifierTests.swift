import XCTest
@testable import BurritoCursorCore

final class PoseClassifierTests: XCTestCase {
    func testPointingPose() {
        let hand = HandBuilder.makeHand(indexBendDeg: 180, middleBendDeg: 60)
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .pointing)
        XCTAssertEqual(pose.indexAngleDeg, 180, accuracy: 5)
    }

    func testScrollingPose() {
        let hand = HandBuilder.makeHand(
            indexBendDeg: 180,
            middleBendDeg: 180,
            ringBendDeg: 60,
            pinkyBendDeg: 60
        )
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .scrolling)
    }

    func testIndexBentClickCandidate() {
        let hand = HandBuilder.makeHand(indexBendDeg: 130, middleBendDeg: 60)
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .indexBent)
        XCTAssertLessThan(pose.indexAngleDeg, 140)
    }

    func testNoFingerExtendedUnknown() {
        let hand = HandBuilder.makeHand(
            indexBendDeg: 60,
            middleBendDeg: 60,
            ringBendDeg: 60,
            pinkyBendDeg: 60
        )
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .unknown)
    }

    func testFingerAngleCalculation() {
        // 180° is fully straight
        let straight = HandBuilder.makeHand(indexBendDeg: 180)
        XCTAssertEqual(
            PoseClassifier.fingerAngleDeg(straight, mcp: .indexMCP, pip: .indexPIP, tip: .indexTip),
            180, accuracy: 0.5
        )
        // 90° bend
        let bent = HandBuilder.makeHand(indexBendDeg: 90)
        XCTAssertEqual(
            PoseClassifier.fingerAngleDeg(bent, mcp: .indexMCP, pip: .indexPIP, tip: .indexTip),
            90, accuracy: 0.5
        )
    }
}
