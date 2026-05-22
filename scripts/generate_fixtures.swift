#!/usr/bin/env swift
// Generates JSON test fixtures for GestureRecognizer regression coverage.
// Run from repo root: swift scripts/generate_fixtures.swift

import Foundation

struct Pt: Codable {
    var x: Double
    var y: Double
    var confidence: Double
}

struct Obs: Codable {
    var timestampSec: Double
    var points: [String: Pt]
}

func frame(t: Double, indexBend: Double, pinching: Bool = false, anchorX: Double = 0.5, anchorY: Double = 0.5, conf: Double = 1.0, middleBend: Double = 60) -> Obs {
    func finger(mcpX: Double, mcpY: Double, bendDeg: Double) -> (Pt, Pt, Pt, Pt) {
        let mcp = Pt(x: mcpX, y: mcpY, confidence: conf)
        let pip = Pt(x: mcpX, y: mcpY + 0.05, confidence: conf)
        let angleRad = (180 - bendDeg) * .pi / 180
        let tipX = mcpX + 0.05 * sin(angleRad)
        let tipY = (mcpY + 0.05) + 0.05 * cos(angleRad)
        let dip = Pt(x: (pip.x + tipX) / 2, y: (pip.y + tipY) / 2, confidence: conf)
        let tip = Pt(x: tipX, y: tipY, confidence: conf)
        return (mcp, pip, dip, tip)
    }
    var pts: [String: Pt] = [:]
    let (im, ip, id, it) = finger(mcpX: anchorX, mcpY: anchorY, bendDeg: indexBend)
    pts["indexMCP"] = im; pts["indexPIP"] = ip; pts["indexDIP"] = id; pts["indexTip"] = it
    let (mm, mp, md, mt) = finger(mcpX: anchorX + 0.02, mcpY: anchorY, bendDeg: middleBend)
    pts["middleMCP"] = mm; pts["middlePIP"] = mp; pts["middleDIP"] = md; pts["middleTip"] = mt
    let (rm, rp, rd, rt) = finger(mcpX: anchorX + 0.04, mcpY: anchorY, bendDeg: 60)
    pts["ringMCP"] = rm; pts["ringPIP"] = rp; pts["ringDIP"] = rd; pts["ringTip"] = rt
    let (pm, pp, pd, pt) = finger(mcpX: anchorX + 0.06, mcpY: anchorY, bendDeg: 60)
    pts["pinkyMCP"] = pm; pts["pinkyPIP"] = pp; pts["pinkyDIP"] = pd; pts["pinkyTip"] = pt
    let wrist = Pt(x: anchorX + 0.03, y: anchorY - 0.2, confidence: conf)
    pts["wrist"] = wrist

    // Thumb: tip at indexTip when pinching, otherwise out to the side.
    let thumbTip: Pt
    if pinching {
        thumbTip = it
    } else {
        thumbTip = Pt(x: anchorX - 0.10, y: anchorY - 0.02, confidence: conf)
    }
    let thumbCMC = wrist
    let mpFrac = 0.4, ipFrac = 0.7
    pts["thumbCMC"] = thumbCMC
    pts["thumbMP"] = Pt(
        x: thumbCMC.x + (thumbTip.x - thumbCMC.x) * mpFrac,
        y: thumbCMC.y + (thumbTip.y - thumbCMC.y) * mpFrac,
        confidence: conf
    )
    pts["thumbIP"] = Pt(
        x: thumbCMC.x + (thumbTip.x - thumbCMC.x) * ipFrac,
        y: thumbCMC.y + (thumbTip.y - thumbCMC.y) * ipFrac,
        confidence: conf
    )
    pts["thumbTip"] = thumbTip
    return Obs(timestampSec: t, points: pts)
}

func write(_ frames: [Obs], to path: String) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try! enc.encode(frames)
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(frames.count) frames)")
}

let dir = "Tests/BurritoCursorCoreTests/Fixtures"

// trace_clean_click: 5 pointing → 5 pinching → 5 pointing
var clean: [Obs] = []
for i in 0..<5 { clean.append(frame(t: Double(i)/30, indexBend: 180)) }
for i in 5..<10 { clean.append(frame(t: Double(i)/30, indexBend: 180, pinching: true)) }
for i in 10..<15 { clean.append(frame(t: Double(i)/30, indexBend: 180)) }
write(clean, to: "\(dir)/trace_clean_click.json")

// trace_confidence_drop_mid_click: pointing → pinch → confidence drops
var drop: [Obs] = []
for i in 0..<5 { drop.append(frame(t: Double(i)/30, indexBend: 180)) }
for i in 5..<10 { drop.append(frame(t: Double(i)/30, indexBend: 180, pinching: true)) }
for i in 10..<13 { drop.append(frame(t: Double(i)/30, indexBend: 180, pinching: true, conf: 0.1)) }
write(drop, to: "\(dir)/trace_confidence_drop_mid_click.json")

// trace_hand_swap: pointing → hand teleports
var swap: [Obs] = []
for i in 0..<5 { swap.append(frame(t: Double(i)/30, indexBend: 180)) }
swap.append(frame(t: 5.0/30, indexBend: 180, anchorX: 0.1, anchorY: 0.1))
for i in 6..<10 { swap.append(frame(t: Double(i)/30, indexBend: 180, anchorX: 0.1, anchorY: 0.1)) }
write(swap, to: "\(dir)/trace_hand_swap.json")

print("Done.")
