import Foundation
@testable import BurritoCursorCore

/// Test helper: builds a synthetic `HandObservation` with custom finger angles.
/// 180° = straight, 0° = fully folded.
enum HandBuilder {
    static func makeHand(
        indexBendDeg: Double = 180,
        middleBendDeg: Double = 60,
        ringBendDeg: Double = 60,
        pinkyBendDeg: Double = 60,
        thumbBendDeg: Double = 180,
        pinching: Bool = false,
        mcpAnchorX: Double = 0.5,
        mcpAnchorY: Double = 0.5,
        timestamp: Double = 0,
        confidence: Double = 1.0
    ) -> HandObservation {
        var pts: [JointName: NormalizedPoint] = [:]

        let fingers: [(mcp: JointName, pip: JointName, dip: JointName, tip: JointName, offsetX: Double, bend: Double)] = [
            (.indexMCP,  .indexPIP,  .indexDIP,  .indexTip,  0.00, indexBendDeg),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, 0.02, middleBendDeg),
            (.ringMCP,   .ringPIP,   .ringDIP,   .ringTip,   0.04, ringBendDeg),
            (.pinkyMCP,  .pinkyPIP,  .pinkyDIP,  .pinkyTip,  0.06, pinkyBendDeg),
        ]
        for f in fingers {
            let mcpX = mcpAnchorX + f.offsetX
            let mcp = NormalizedPoint(x: mcpX, y: mcpAnchorY, confidence: confidence)
            let pip = NormalizedPoint(x: mcpX, y: mcpAnchorY + 0.05, confidence: confidence)
            let angleRad = (180.0 - f.bend) * .pi / 180.0
            let tipX = mcpX + 0.05 * sin(angleRad)
            let tipY = (mcpAnchorY + 0.05) + 0.05 * cos(angleRad)
            // Synthetic DIP at midpoint between PIP and TIP — keeps 3-segment
            // curl_ratio computation working without changing the geometry.
            let dip = NormalizedPoint(
                x: (pip.x + tipX) / 2,
                y: (pip.y + tipY) / 2,
                confidence: confidence
            )
            let tip = NormalizedPoint(x: tipX, y: tipY, confidence: confidence)
            pts[f.mcp] = mcp
            pts[f.pip] = pip
            pts[f.dip] = dip
            pts[f.tip] = tip
        }
        let wrist = NormalizedPoint(x: mcpAnchorX + 0.03, y: mcpAnchorY - 0.2, confidence: confidence)
        pts[.wrist] = wrist

        // Thumb landmarks. Tip lands at:
        //   - indexTip position when `pinching` is true (zero pinchDistance)
        //   - default "out to the side" position otherwise
        // Other thumb joints are linearly interpolated from CMC (at wrist) to Tip.
        let thumbTipPos: NormalizedPoint
        if pinching, let indexTip = pts[.indexTip] {
            thumbTipPos = indexTip
        } else {
            thumbTipPos = NormalizedPoint(
                x: mcpAnchorX - 0.10,
                y: mcpAnchorY - 0.02,
                confidence: confidence
            )
        }
        let thumbCMC = wrist
        let bendFactor = max(0, min(1, (180.0 - thumbBendDeg) / 180.0))
        // When thumbBendDeg < 180, IP/MP collapse toward CMC to simulate curl.
        let mpFraction = 0.4 * (1.0 - bendFactor * 0.6)
        let ipFraction = 0.7 * (1.0 - bendFactor * 0.6)
        pts[.thumbCMC] = thumbCMC
        pts[.thumbMP] = NormalizedPoint(
            x: thumbCMC.x + (thumbTipPos.x - thumbCMC.x) * mpFraction,
            y: thumbCMC.y + (thumbTipPos.y - thumbCMC.y) * mpFraction,
            confidence: confidence
        )
        pts[.thumbIP] = NormalizedPoint(
            x: thumbCMC.x + (thumbTipPos.x - thumbCMC.x) * ipFraction,
            y: thumbCMC.y + (thumbTipPos.y - thumbCMC.y) * ipFraction,
            confidence: confidence
        )
        pts[.thumbTip] = thumbTipPos

        return HandObservation(timestampSec: timestamp, points: pts)
    }
}
