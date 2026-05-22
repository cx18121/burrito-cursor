import XCTest
@testable import BurritoCursorCore

final class TraceReplayTests: XCTestCase {
    func testCleanClickTrace() throws {
        let kinds = try replay("trace_clean_click").map(kindLabel)
        XCTAssertTrue(kinds.contains("pointing"), "Trace should reach .pointing")
        XCTAssertTrue(kinds.contains("clicking"), "Trace should reach .clicking")
        let clickIdx = kinds.firstIndex(of: "clicking")!
        let afterClick = kinds[clickIdx...].drop(while: { $0 == "clicking" })
        XCTAssertEqual(afterClick.first, "pointing", "After clicking the state should return to .pointing")
    }

    func testConfidenceDropMidClick() throws {
        let kinds = try replay("trace_confidence_drop_mid_click").map(kindLabel)
        XCTAssertTrue(kinds.contains("clicking"), "Trace should reach .clicking")
        XCTAssertTrue(kinds.contains("degraded"), "Mid-click confidence drop must enter .degraded")
    }

    func testHandSwap() throws {
        let kinds = try replay("trace_hand_swap").map(kindLabel)
        XCTAssertTrue(kinds.contains("idle"), "Hand jump must reset to .idle at some point")
    }

    // MARK: - Helpers

    private func replay(_ fixtureName: String) throws -> [GestureState] {
        guard let url = Bundle.module.url(
            forResource: fixtureName,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            XCTFail("Fixture not found: \(fixtureName).json")
            return []
        }
        let data = try Data(contentsOf: url)
        let trace = try JSONDecoder().decode([HandObservation].self, from: data)
        let r = GestureRecognizer(config: .defaults)
        return trace.map { r.step($0) }
    }

    private func kindLabel(_ s: GestureState) -> String {
        switch s {
        case .idle: return "idle"
        case .pointing: return "pointing"
        case .clicking: return "clicking"
        case .scrolling: return "scrolling"
        case .degraded: return "degraded"
        }
    }
}
