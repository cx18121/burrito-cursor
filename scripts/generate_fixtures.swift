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

func frame(t: Double, indexBend: Double, anchorX: Double = 0.5, anchorY: Double = 0.5, conf: Double = 1.0, middleBend: Double = 60) -> Obs {
    func finger(mcpX: Double, mcpY: Double, bendDeg: Double) -> (Pt, Pt, Pt) {
        let mcp = Pt(x: mcpX, y: mcpY, confidence: conf)
        let pip = Pt(x: mcpX, y: mcpY + 0.05, confidence: conf)
        let angleRad = (180 - bendDeg) * .pi / 180
        let tipX = mcpX + 0.05 * sin(angleRad)
        let tipY = (mcpY + 0.05) + 0.05 * cos(angleRad)
        let tip = Pt(x: tipX, y: tipY, confidence: conf)
        return (mcp, pip, tip)
    }
    var pts: [String: Pt] = [:]
    let (im, ip, it) = finger(mcpX: anchorX, mcpY: anchorY, bendDeg: indexBend)
    pts["indexMCP"] = im; pts["indexPIP"] = ip; pts["indexTip"] = it
    let (mm, mp, mt) = finger(mcpX: anchorX + 0.02, mcpY: anchorY, bendDeg: middleBend)
    pts["middleMCP"] = mm; pts["middlePIP"] = mp; pts["middleTip"] = mt
    let (rm, rp, rt) = finger(mcpX: anchorX + 0.04, mcpY: anchorY, bendDeg: 60)
    pts["ringMCP"] = rm; pts["ringPIP"] = rp; pts["ringTip"] = rt
    let (pm, pp, pt) = finger(mcpX: anchorX + 0.06, mcpY: anchorY, bendDeg: 60)
    pts["pinkyMCP"] = pm; pts["pinkyPIP"] = pp; pts["pinkyTip"] = pt
    pts["wrist"] = Pt(x: anchorX + 0.03, y: anchorY - 0.2, confidence: conf)
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

// trace_clean_click: 5 pointing → 1 latch (bend 110°) → 4 click (bend 90°) → 5 pointing
// curl_ratio: pointing 1.0, latch 1.22, click 1.41
var clean: [Obs] = []
for i in 0..<5 { clean.append(frame(t: Double(i)/30, indexBend: 180)) }
clean.append(frame(t: 5.0/30, indexBend: 110))
for i in 6..<10 { clean.append(frame(t: Double(i)/30, indexBend: 90)) }
for i in 10..<15 { clean.append(frame(t: Double(i)/30, indexBend: 180)) }
write(clean, to: "\(dir)/trace_clean_click.json")

// trace_confidence_drop_mid_click: pointing → click → confidence drops
var drop: [Obs] = []
for i in 0..<5 { drop.append(frame(t: Double(i)/30, indexBend: 180)) }
drop.append(frame(t: 5.0/30, indexBend: 110))
for i in 6..<10 { drop.append(frame(t: Double(i)/30, indexBend: 90)) }
for i in 10..<13 { drop.append(frame(t: Double(i)/30, indexBend: 90, conf: 0.1)) }
write(drop, to: "\(dir)/trace_confidence_drop_mid_click.json")

// trace_hand_swap: pointing → hand teleports
var swap: [Obs] = []
for i in 0..<5 { swap.append(frame(t: Double(i)/30, indexBend: 180)) }
swap.append(frame(t: 5.0/30, indexBend: 180, anchorX: 0.1, anchorY: 0.1))
for i in 6..<10 { swap.append(frame(t: Double(i)/30, indexBend: 180, anchorX: 0.1, anchorY: 0.1)) }
write(swap, to: "\(dir)/trace_hand_swap.json")

print("Done.")
