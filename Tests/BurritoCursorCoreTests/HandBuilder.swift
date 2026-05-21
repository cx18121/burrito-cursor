import Foundation
@testable import BurritoCursorCore

/// Test helper: builds a synthetic `HandObservation` with custom finger angles.
/// 180° = straight, 0° = fully folded. MCP→PIP→TIP angle of the resulting hand equals `bendDeg`.
enum HandBuilder {
    static func makeHand(
        indexBendDeg: Double = 180,
        middleBendDeg: Double = 60,
        ringBendDeg: Double = 60,
        pinkyBendDeg: Double = 60,
        mcpAnchorX: Double = 0.5,
        mcpAnchorY: Double = 0.5,
        timestamp: Double = 0,
        confidence: Double = 1.0
    ) -> HandObservation {
        var pts: [JointName: NormalizedPoint] = [:]

        let fingers: [(mcp: JointName, pip: JointName, tip: JointName, offsetX: Double, bend: Double)] = [
            (.indexMCP, .indexPIP, .indexTip, 0.00, indexBendDeg),
            (.middleMCP, .middlePIP, .middleTip, 0.02, middleBendDeg),
            (.ringMCP, .ringPIP, .ringTip, 0.04, ringBendDeg),
            (.pinkyMCP, .pinkyPIP, .pinkyTip, 0.06, pinkyBendDeg),
        ]

        for f in fingers {
            let mcpX = mcpAnchorX + f.offsetX
            let mcp = NormalizedPoint(x: mcpX, y: mcpAnchorY, confidence: confidence)
            let pip = NormalizedPoint(x: mcpX, y: mcpAnchorY + 0.05, confidence: confidence)
            let angleRad = (180.0 - f.bend) * .pi / 180.0
            let tipX = mcpX + 0.05 * sin(angleRad)
            let tipY = (mcpAnchorY + 0.05) + 0.05 * cos(angleRad)
            let tip = NormalizedPoint(x: tipX, y: tipY, confidence: confidence)
            pts[f.mcp] = mcp
            pts[f.pip] = pip
            pts[f.tip] = tip
        }
        pts[.wrist] = NormalizedPoint(x: mcpAnchorX + 0.03, y: mcpAnchorY - 0.2, confidence: confidence)
        return HandObservation(timestampSec: timestamp, points: pts)
    }
}
