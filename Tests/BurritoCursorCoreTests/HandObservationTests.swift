import XCTest
@testable import BurritoCursorCore

final class HandObservationTests: XCTestCase {
    func testRoundtripJSON() throws {
        let obs = HandObservation(
            timestampSec: 1.23,
            points: [
                .indexMCP: NormalizedPoint(x: 0.5, y: 0.5, confidence: 0.9),
                .indexTip: NormalizedPoint(x: 0.5, y: 0.7, confidence: 0.85),
            ]
        )
        let data = try JSONEncoder().encode(obs)
        let decoded = try JSONDecoder().decode(HandObservation.self, from: data)
        XCTAssertEqual(decoded, obs)
    }

    func testMinConfidenceOfEmptyIsZero() {
        let empty = HandObservation(timestampSec: 0, points: [:])
        XCTAssertEqual(empty.minConfidence, 0.0)
    }

    func testMinConfidenceTakesMinimum() {
        let obs = HandObservation(timestampSec: 0, points: [
            .indexMCP: NormalizedPoint(x: 0, y: 0, confidence: 0.9),
            .indexTip: NormalizedPoint(x: 0, y: 0, confidence: 0.2),
            .middleMCP: NormalizedPoint(x: 0, y: 0, confidence: 0.7),
        ])
        XCTAssertEqual(obs.minConfidence, 0.2)
    }

    func testGestureStateEquality() {
        XCTAssertEqual(GestureState.idle, GestureState.idle)
        XCTAssertNotEqual(
            GestureState.pointing(point: NormalizedPoint(x: 0, y: 0, confidence: 1)),
            GestureState.idle
        )
    }
}
