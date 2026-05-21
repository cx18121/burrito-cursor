# Burrito-cursor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that translates webcam hand gestures into cursor movement, click, and scroll events, so the user can control their Mac with messy hands.

**Architecture:** Swift Package Manager executable target. Pipeline: `AVCaptureSession → VNDetectHumanHandPoseRequest → pure-function GestureRecognizer → InputCoordinator → CursorController / ScrollController (CGEvent)`. Pure logic in a separate `BurritoCursorCore` library so it can be unit-tested without launching a camera. App orchestration in `BurritoCursor` executable. Manual UAT for camera/Vision/CGEvent paths.

**Tech Stack:** Swift 5.9+, AppKit (`NSStatusItem`, `NSPanel`), AVFoundation, Vision, CoreGraphics (`CGEvent`), XCTest, [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) package for global hotkey. macOS 13+ deployment target.

**Prerequisites:** Xcode 15+ command-line tools (`xcode-select --install`), Swift 5.9+ (comes with Xcode). No other tools required — SPM-only, no XcodeGen, no CocoaPods.

**Spec:** [`2026-05-21-burrito-cursor-design.md`](../specs/2026-05-21-burrito-cursor-design.md)

**Working directory for all commands:** `/Users/charliexue/School/cs_misc/burrito-cursor/`

---

## Phase 1 — Project foundation

### Task 1: Scaffold the Swift Package

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Resources/Info.plist`
- Create: `Sources/BurritoCursorCore/.gitkeep`
- Create: `Sources/BurritoCursor/main.swift`
- Create: `Tests/BurritoCursorCoreTests/.gitkeep`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BurritoCursor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BurritoCursor", targets: ["BurritoCursor"]),
        .library(name: "BurritoCursorCore", targets: ["BurritoCursorCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BurritoCursor",
            dependencies: [
                "BurritoCursorCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [.copy("../../Resources/Info.plist")]
        ),
        .target(name: "BurritoCursorCore"),
        .testTarget(name: "BurritoCursorCoreTests", dependencies: ["BurritoCursorCore"]),
    ]
)
```

- [ ] **Step 2: Write `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj/
*.xcworkspace/
DerivedData/
.DS_Store
BurritoCursor.app/
*.dmg
```

- [ ] **Step 3: Write `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.charliexue.burritocursor</string>
    <key>CFBundleName</key>
    <string>BurritoCursor</string>
    <key>CFBundleDisplayName</key>
    <string>Burrito Cursor</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Burrito Cursor uses the camera to detect hand gestures for cursor control.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Write `Sources/BurritoCursor/main.swift` (stub)**

```swift
import AppKit

print("BurritoCursor starting…")
// Real entry point installed in Task 14.
exit(0)
```

- [ ] **Step 5: Create empty marker files for the empty source/test dirs**

```bash
touch Sources/BurritoCursorCore/.gitkeep
touch Tests/BurritoCursorCoreTests/.gitkeep
```

- [ ] **Step 6: Verify it builds**

Run: `swift build`
Expected: builds successfully, downloads KeyboardShortcuts dep. No errors.

- [ ] **Step 7: Verify tests run (empty suite is fine)**

Run: `swift test`
Expected: "Test Suite 'All tests' passed" with 0 tests.

- [ ] **Step 8: Commit**

```bash
git add Package.swift .gitignore Resources Sources Tests
git commit -m "Scaffold Swift Package structure"
```

---

### Task 2: `Config` struct with `UserDefaults` loading

**Files:**
- Create: `Sources/BurritoCursorCore/Config.swift`
- Create: `Tests/BurritoCursorCoreTests/ConfigTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/BurritoCursorCoreTests/ConfigTests.swift`:

```swift
import XCTest
@testable import BurritoCursorCore

final class ConfigTests: XCTestCase {
    func testDefaultsMatchSpec() {
        let cfg = Config.defaults
        XCTAssertEqual(cfg.sensitivity, 1.0)
        XCTAssertEqual(cfg.deadzoneNormalized, 0.005)
        XCTAssertEqual(cfg.debounceEntryFrames, 3)
        XCTAssertEqual(cfg.debounceExitFrames, 1)
        XCTAssertEqual(cfg.clickEnterAngleDeg, 140.0)
        XCTAssertEqual(cfg.clickExitAngleDeg, 155.0)
        XCTAssertEqual(cfg.degradedConfidenceThreshold, 0.3)
        XCTAssertEqual(cfg.handJumpRejectionFraction, 0.25)
        XCTAssertEqual(cfg.scrollSensitivity, 1.0)
        XCTAssertEqual(cfg.oneEuroBeta, 0.007)
        XCTAssertEqual(cfg.oneEuroMinCutoff, 1.0)
    }

    func testLoadFromInMemoryStore() {
        let store = InMemoryKVStore([
            "sensitivity": 2.5,
            "deadzoneNormalized": 0.01,
        ])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.sensitivity, 2.5)
        XCTAssertEqual(cfg.deadzoneNormalized, 0.01)
        // Untouched keys fall back to defaults
        XCTAssertEqual(cfg.clickEnterAngleDeg, 140.0)
    }

    func testInvariantsClampOrReject() {
        // Sensitivity must be positive
        let store = InMemoryKVStore(["sensitivity": -1.0])
        let cfg = Config.load(from: store)
        XCTAssertEqual(cfg.sensitivity, 1.0, "Negative sensitivity must fall back to default")
    }
}

// Test helper — simulates UserDefaults without touching the real store.
final class InMemoryKVStore: KVStore {
    private var dict: [String: Any]
    init(_ dict: [String: Any] = [:]) { self.dict = dict }
    func object(forKey key: String) -> Any? { dict[key] }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test`
Expected: build error — `Config` / `KVStore` / `InMemoryKVStore` undefined.

- [ ] **Step 3: Implement `Config`**

`Sources/BurritoCursorCore/Config.swift`:

```swift
import Foundation

public protocol KVStore {
    func object(forKey key: String) -> Any?
}

extension UserDefaults: KVStore {}

public struct Config: Equatable {
    public var sensitivity: Double
    public var deadzoneNormalized: Double
    public var debounceEntryFrames: Int
    public var debounceExitFrames: Int
    public var clickEnterAngleDeg: Double
    public var clickExitAngleDeg: Double
    public var degradedConfidenceThreshold: Double
    public var handJumpRejectionFraction: Double
    public var scrollSensitivity: Double
    public var oneEuroBeta: Double
    public var oneEuroMinCutoff: Double

    public static let defaults = Config(
        sensitivity: 1.0,
        deadzoneNormalized: 0.005,
        debounceEntryFrames: 3,
        debounceExitFrames: 1,
        clickEnterAngleDeg: 140.0,
        clickExitAngleDeg: 155.0,
        degradedConfidenceThreshold: 0.3,
        handJumpRejectionFraction: 0.25,
        scrollSensitivity: 1.0,
        oneEuroBeta: 0.007,
        oneEuroMinCutoff: 1.0
    )

    public static func load(from store: KVStore) -> Config {
        var c = Config.defaults
        if let v = store.object(forKey: "sensitivity") as? Double, v > 0 { c.sensitivity = v }
        if let v = store.object(forKey: "deadzoneNormalized") as? Double, v >= 0 { c.deadzoneNormalized = v }
        if let v = store.object(forKey: "debounceEntryFrames") as? Int, v >= 1 { c.debounceEntryFrames = v }
        if let v = store.object(forKey: "debounceExitFrames") as? Int, v >= 1 { c.debounceExitFrames = v }
        if let v = store.object(forKey: "clickEnterAngleDeg") as? Double { c.clickEnterAngleDeg = v }
        if let v = store.object(forKey: "clickExitAngleDeg") as? Double { c.clickExitAngleDeg = v }
        if let v = store.object(forKey: "degradedConfidenceThreshold") as? Double { c.degradedConfidenceThreshold = v }
        if let v = store.object(forKey: "handJumpRejectionFraction") as? Double, v > 0 { c.handJumpRejectionFraction = v }
        if let v = store.object(forKey: "scrollSensitivity") as? Double, v > 0 { c.scrollSensitivity = v }
        if let v = store.object(forKey: "oneEuroBeta") as? Double { c.oneEuroBeta = v }
        if let v = store.object(forKey: "oneEuroMinCutoff") as? Double { c.oneEuroMinCutoff = v }
        return c
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `swift test`
Expected: 3 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursorCore/Config.swift Tests/BurritoCursorCoreTests/ConfigTests.swift
git commit -m "Add Config struct with UserDefaults loading"
```

---

### Task 3: One Euro Filter

The One Euro Filter (Casiez et al., 2012) smooths noisy real-time signals with low latency. Standard reference for cursor smoothing. We implement it once, test thoroughly, then reuse.

**Files:**
- Create: `Sources/BurritoCursorCore/OneEuroFilter.swift`
- Create: `Tests/BurritoCursorCoreTests/OneEuroFilterTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/BurritoCursorCoreTests/OneEuroFilterTests.swift`:

```swift
import XCTest
@testable import BurritoCursorCore

final class OneEuroFilterTests: XCTestCase {
    func testFirstSampleReturnsItself() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007)
        let y = f.filter(5.0, timestampSec: 0.0)
        XCTAssertEqual(y, 5.0, accuracy: 1e-9)
    }

    func testConstantSignalConverges() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007)
        var last = 0.0
        for i in 0..<100 {
            last = f.filter(10.0, timestampSec: Double(i) * 1.0 / 30.0)
        }
        XCTAssertEqual(last, 10.0, accuracy: 1e-3)
    }

    func testSlowMotionGetsSmoothedHard() {
        // Square wave: filter should attenuate high-frequency hops when slow
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.0)
        var ys: [Double] = []
        for i in 0..<10 {
            let sample = i.isMultiple(of: 2) ? 0.0 : 1.0
            ys.append(f.filter(sample, timestampSec: Double(i) * 1.0 / 30.0))
        }
        // No filtered sample should reach the raw amplitude of 1.0 instantly
        XCTAssertLessThan(ys.last!, 1.0)
        XCTAssertGreaterThan(ys.last!, 0.0)
    }

    func testFastMotionPassesThrough() {
        // High velocity → high cutoff via beta → less filtering
        var f = OneEuroFilter(minCutoff: 1.0, beta: 1.0)
        _ = f.filter(0.0, timestampSec: 0.0)
        let y = f.filter(100.0, timestampSec: 0.01) // big jump in small time
        XCTAssertGreaterThan(y, 50.0, "Fast motion should pass through with low latency")
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test`
Expected: build error — `OneEuroFilter` undefined.

- [ ] **Step 3: Implement `OneEuroFilter`**

`Sources/BurritoCursorCore/OneEuroFilter.swift`:

```swift
import Foundation

/// One Euro Filter — Casiez, Roussel, Vogel 2012.
/// Smooths noisy real-time signals. Adapts cutoff frequency based on signal velocity:
/// slow motion → strong smoothing, fast motion → low latency.
public struct OneEuroFilter {
    private let minCutoff: Double  // Hz
    private let beta: Double
    private let dCutoff: Double = 1.0

    private var prevValue: Double?
    private var prevDerivative: Double = 0.0
    private var prevTimestamp: Double?

    public init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    public mutating func filter(_ x: Double, timestampSec t: Double) -> Double {
        guard let prevT = prevTimestamp, let prevX = prevValue else {
            prevValue = x
            prevTimestamp = t
            return x
        }
        let dt = max(t - prevT, 1e-6)
        let dx = (x - prevX) / dt
        // Smooth the derivative
        let edx = lowpass(dx, prev: prevDerivative, alpha: smoothingAlpha(cutoff: dCutoff, dt: dt))
        // Compute adaptive cutoff
        let cutoff = minCutoff + beta * abs(edx)
        let ex = lowpass(x, prev: prevX, alpha: smoothingAlpha(cutoff: cutoff, dt: dt))

        prevValue = ex
        prevDerivative = edx
        prevTimestamp = t
        return ex
    }

    private func smoothingAlpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private func lowpass(_ x: Double, prev: Double, alpha: Double) -> Double {
        return alpha * x + (1.0 - alpha) * prev
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `swift test`
Expected: 4 tests passing in `OneEuroFilterTests`.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursorCore/OneEuroFilter.swift Tests/BurritoCursorCoreTests/OneEuroFilterTests.swift
git commit -m "Add One Euro Filter with smoothing tests"
```

---

## Phase 2 — Recognizer types and logic

### Task 4: Core types — `HandObservation`, `GestureState`, `JointName`

**Files:**
- Create: `Sources/BurritoCursorCore/HandObservation.swift`
- Create: `Sources/BurritoCursorCore/GestureState.swift`
- Create: `Tests/BurritoCursorCoreTests/HandObservationTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/BurritoCursorCoreTests/HandObservationTests.swift`:

```swift
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

    func testGestureStateEquality() {
        XCTAssertEqual(GestureState.idle, GestureState.idle)
        XCTAssertNotEqual(
            GestureState.pointing(point: NormalizedPoint(x: 0, y: 0, confidence: 1)),
            GestureState.idle
        )
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test`
Expected: build errors — types undefined.

- [ ] **Step 3: Implement types**

`Sources/BurritoCursorCore/HandObservation.swift`:

```swift
import Foundation

public enum JointName: String, Codable, CaseIterable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case pinkyMCP, pinkyPIP, pinkyDIP, pinkyTip
}

public struct NormalizedPoint: Codable, Equatable {
    /// Image-space coords, origin bottom-left, range [0,1]. x is pre-mirrored to match screen orientation.
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public struct HandObservation: Codable, Equatable {
    public var timestampSec: Double
    public var points: [JointName: NormalizedPoint]

    public init(timestampSec: Double, points: [JointName: NormalizedPoint]) {
        self.timestampSec = timestampSec
        self.points = points
    }

    public var minConfidence: Double {
        points.values.map { $0.confidence }.min() ?? 0.0
    }
}
```

`Sources/BurritoCursorCore/GestureState.swift`:

```swift
import Foundation

public enum GestureState: Equatable {
    case idle
    case pointing(point: NormalizedPoint)
    case clickLatched(point: NormalizedPoint)
    case clicking(point: NormalizedPoint)
    case scrolling(deltaY: Double, point: NormalizedPoint)
    case degraded(previous: PreviousNonDegraded)

    public enum PreviousNonDegraded: Equatable {
        case idle
        case pointing(point: NormalizedPoint)
        case clickLatched(point: NormalizedPoint)
        case clicking(point: NormalizedPoint)
        case scrolling(point: NormalizedPoint)
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `swift test`
Expected: 2 new tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursorCore/HandObservation.swift Sources/BurritoCursorCore/GestureState.swift Tests/BurritoCursorCoreTests/HandObservationTests.swift
git commit -m "Add core types: HandObservation, JointName, GestureState"
```

---

### Task 5: Pose classifier — extended/curled detection

This is the per-frame primitive: given one `HandObservation`, classify what pose the hand is in. The state machine in Task 6 consumes this.

**Files:**
- Create: `Sources/BurritoCursorCore/PoseClassifier.swift`
- Create: `Tests/BurritoCursorCoreTests/PoseClassifierTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/BurritoCursorCoreTests/PoseClassifierTests.swift`:

```swift
import XCTest
@testable import BurritoCursorCore

final class PoseClassifierTests: XCTestCase {
    /// Helper: build a hand with explicit finger angles. Each finger represented
    /// as a straight line in y, with `bendAngleDeg` controlling tip position.
    func makeHand(
        indexBendDeg: Double = 180,
        middleBendDeg: Double = 60,
        ringBendDeg: Double = 60,
        pinkyBendDeg: Double = 60,
        timestamp: Double = 0
    ) -> HandObservation {
        func finger(mcpX: Double, bendDeg: Double) -> [JointName: NormalizedPoint] {
            // MCP at (mcpX, 0.5). PIP straight up. Tip rotated by (180 - bendDeg) from straight.
            let mcp = NormalizedPoint(x: mcpX, y: 0.5, confidence: 1.0)
            let pip = NormalizedPoint(x: mcpX, y: 0.55, confidence: 1.0)
            let angleRad = (180.0 - bendDeg) * .pi / 180.0
            let tipX = mcpX + 0.05 * sin(angleRad)
            let tipY = 0.55 + 0.05 * cos(angleRad)
            let tip = NormalizedPoint(x: tipX, y: tipY, confidence: 1.0)
            return [.indexMCP: mcp, .indexPIP: pip, .indexTip: tip]
        }

        var pts: [JointName: NormalizedPoint] = [:]
        // Index
        let index = finger(mcpX: 0.5, bendDeg: indexBendDeg)
        pts[.indexMCP] = index[.indexMCP]
        pts[.indexPIP] = index[.indexPIP]
        pts[.indexTip] = index[.indexTip]
        // Middle (reuse with key remapping)
        let middle = finger(mcpX: 0.52, bendDeg: middleBendDeg)
        pts[.middleMCP] = middle[.indexMCP]
        pts[.middlePIP] = middle[.indexPIP]
        pts[.middleTip] = middle[.indexTip]
        // Ring
        let ring = finger(mcpX: 0.54, bendDeg: ringBendDeg)
        pts[.ringMCP] = ring[.indexMCP]
        pts[.ringPIP] = ring[.indexPIP]
        pts[.ringTip] = ring[.indexTip]
        // Pinky
        let pinky = finger(mcpX: 0.56, bendDeg: pinkyBendDeg)
        pts[.pinkyMCP] = pinky[.indexMCP]
        pts[.pinkyPIP] = pinky[.indexPIP]
        pts[.pinkyTip] = pinky[.indexTip]
        pts[.wrist] = NormalizedPoint(x: 0.53, y: 0.3, confidence: 1.0)
        return HandObservation(timestampSec: timestamp, points: pts)
    }

    func testPointingPose() {
        let hand = makeHand(indexBendDeg: 180, middleBendDeg: 60)
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .pointing)
        XCTAssertEqual(pose.indexAngleDeg, 180, accuracy: 5)
    }

    func testScrollingPose() {
        let hand = makeHand(indexBendDeg: 180, middleBendDeg: 180, ringBendDeg: 60, pinkyBendDeg: 60)
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .scrolling)
    }

    func testIndexBent_clickCandidate() {
        let hand = makeHand(indexBendDeg: 130, middleBendDeg: 60)
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .indexBent)
        XCTAssertLessThan(pose.indexAngleDeg, 140)
    }

    func testNoFingerExtended_unknown() {
        let hand = makeHand(indexBendDeg: 60, middleBendDeg: 60, ringBendDeg: 60, pinkyBendDeg: 60)
        let pose = PoseClassifier.classify(hand)
        XCTAssertEqual(pose.kind, .unknown)
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test`
Expected: build errors — `PoseClassifier` undefined.

- [ ] **Step 3: Implement `PoseClassifier`**

`Sources/BurritoCursorCore/PoseClassifier.swift`:

```swift
import Foundation

public struct ClassifiedPose: Equatable {
    public enum Kind: Equatable {
        case pointing       // index extended, others curled
        case scrolling      // index + middle extended, ring + pinky curled
        case indexBent      // pointing pose but index angle < click threshold (click candidate)
        case unknown        // anything else
    }
    public let kind: Kind
    public let indexAngleDeg: Double
    public let middleAngleDeg: Double
    public let ringAngleDeg: Double
    public let pinkyAngleDeg: Double
}

public enum PoseClassifier {
    /// Per-frame classification. Click-vs-pointing depends on the index angle and
    /// configurable thresholds in Config — but here we just return raw kind +
    /// angles, and the state machine in Task 6 applies hysteresis.
    public static func classify(_ obs: HandObservation) -> ClassifiedPose {
        let idx = fingerAngleDeg(obs, mcp: .indexMCP, pip: .indexPIP, tip: .indexTip)
        let mid = fingerAngleDeg(obs, mcp: .middleMCP, pip: .middlePIP, tip: .middleTip)
        let ring = fingerAngleDeg(obs, mcp: .ringMCP, pip: .ringPIP, tip: .ringTip)
        let pky = fingerAngleDeg(obs, mcp: .pinkyMCP, pip: .pinkyPIP, tip: .pinkyTip)

        let extendedAngle = 160.0   // angle above this == extended
        let curledAngle = 110.0     // angle below this == curled
        let clickThreshold = 140.0  // raw class boundary (state machine applies hysteresis)

        let indexExtended = idx >= extendedAngle
        let indexBent = idx < clickThreshold
        let middleExtended = mid >= extendedAngle
        let middleCurled = mid < curledAngle
        let ringCurled = ring < curledAngle
        let pinkyCurled = pky < curledAngle

        let kind: ClassifiedPose.Kind
        if indexExtended, middleCurled, ringCurled, pinkyCurled {
            kind = .pointing
        } else if indexExtended, middleExtended, ringCurled, pinkyCurled {
            kind = .scrolling
        } else if indexBent, middleCurled, ringCurled, pinkyCurled {
            kind = .indexBent
        } else {
            kind = .unknown
        }
        return ClassifiedPose(
            kind: kind,
            indexAngleDeg: idx,
            middleAngleDeg: mid,
            ringAngleDeg: ring,
            pinkyAngleDeg: pky
        )
    }

    /// Angle MCP→PIP→TIP, in degrees. 180 = fully straight, 0 = fully folded.
    static func fingerAngleDeg(
        _ obs: HandObservation,
        mcp: JointName, pip: JointName, tip: JointName
    ) -> Double {
        guard let m = obs.points[mcp], let p = obs.points[pip], let t = obs.points[tip] else {
            return 0
        }
        let v1x = m.x - p.x
        let v1y = m.y - p.y
        let v2x = t.x - p.x
        let v2y = t.y - p.y
        let dot = v1x * v2x + v1y * v2y
        let mag1 = sqrt(v1x * v1x + v1y * v1y)
        let mag2 = sqrt(v2x * v2x + v2y * v2y)
        guard mag1 > 1e-9, mag2 > 1e-9 else { return 0 }
        let cosA = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosA) * 180.0 / .pi
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `swift test`
Expected: 4 new tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursorCore/PoseClassifier.swift Tests/BurritoCursorCoreTests/PoseClassifierTests.swift
git commit -m "Add PoseClassifier with finger-angle classification"
```

---

### Task 6: `GestureRecognizer` state machine — entry/exit debounce + transitions

This is the heart of the system. Pure function over a sliding window of observations.

**Files:**
- Create: `Sources/BurritoCursorCore/GestureRecognizer.swift`
- Create: `Tests/BurritoCursorCoreTests/GestureRecognizerTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/BurritoCursorCoreTests/GestureRecognizerTests.swift`:

```swift
import XCTest
@testable import BurritoCursorCore

final class GestureRecognizerTests: XCTestCase {
    /// Helper: build a sequence of identical observations spanning N frames at 30fps.
    func sequence(_ obs: HandObservation, frames: Int, startT: Double = 0) -> [HandObservation] {
        (0..<frames).map { i in
            var o = obs
            o.timestampSec = startT + Double(i) / 30.0
            return o
        }
    }

    func pointingHand(at x: Double = 0.5, y: Double = 0.5, t: Double = 0) -> HandObservation {
        var hand = PoseClassifierTests().makeHand(indexBendDeg: 180, middleBendDeg: 60)
        hand.timestampSec = t
        // Shift all points so MCP lands at (x, y)
        let mcp = hand.points[.indexMCP]!
        let dx = x - mcp.x
        let dy = y - mcp.y
        for (k, p) in hand.points {
            hand.points[k] = NormalizedPoint(x: p.x + dx, y: p.y + dy, confidence: p.confidence)
        }
        return hand
    }

    func testRequires3FramesToEnterPointing() {
        var r = GestureRecognizer(config: .defaults)
        // Frame 1 — still idle
        XCTAssertEqual(r.step(pointingHand(t: 0)), .idle)
        // Frame 2 — still idle
        XCTAssertEqual(r.step(pointingHand(t: 1.0/30)), .idle)
        // Frame 3 — promoted to pointing
        if case .pointing = r.step(pointingHand(t: 2.0/30)) {} else {
            XCTFail("Expected .pointing after 3 frames")
        }
    }

    func testNoHand_returnsIdle() {
        var r = GestureRecognizer(config: .defaults)
        // Empty observation → idle
        let empty = HandObservation(timestampSec: 0, points: [:])
        XCTAssertEqual(r.step(empty), .idle)
    }

    func testConfidenceDropEntersDegraded() {
        var r = GestureRecognizer(config: .defaults)
        // Establish pointing
        _ = r.step(pointingHand(t: 0))
        _ = r.step(pointingHand(t: 1.0/30))
        _ = r.step(pointingHand(t: 2.0/30))
        // Drop confidence on next frame
        var lowConf = pointingHand(t: 3.0/30)
        for (k, p) in lowConf.points {
            lowConf.points[k] = NormalizedPoint(x: p.x, y: p.y, confidence: 0.1)
        }
        if case .degraded = r.step(lowConf) {} else {
            XCTFail("Expected .degraded on low confidence")
        }
    }

    func testHandJumpResetsToIdle() {
        var r = GestureRecognizer(config: .defaults)
        // Establish pointing at (0.5, 0.5)
        _ = r.step(pointingHand(at: 0.5, y: 0.5, t: 0))
        _ = r.step(pointingHand(at: 0.5, y: 0.5, t: 1.0/30))
        _ = r.step(pointingHand(at: 0.5, y: 0.5, t: 2.0/30))
        // Suddenly hand appears at (0.1, 0.1) — > 25% frame jump
        let jumped = r.step(pointingHand(at: 0.1, y: 0.1, t: 3.0/30))
        XCTAssertEqual(jumped, .idle, "Hand-jump should reset to .idle")
    }

    func testClickLatchedThenClicking() {
        var r = GestureRecognizer(config: .defaults)
        // Enter .pointing
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        // Pre-threshold latch: simulate index angle dropping from 180 to 150 (below exit 155 but above enter 140)
        let latchHand = handWithIndexAngle(150, at: 0.5, y: 0.5, t: 3.0/30)
        if case .clickLatched = r.step(latchHand) {} else {
            XCTFail("Expected .clickLatched at 150°")
        }
        // Confirm: drop to 130 for 3 frames → .clicking
        for i in 4..<7 {
            let h = handWithIndexAngle(130, at: 0.5, y: 0.5, t: Double(i)/30)
            _ = r.step(h)
        }
        if case .clicking = r.lastState {} else {
            XCTFail("Expected .clicking after sustained bend")
        }
    }

    func testClickReleaseImmediateOnAngleAbove155() {
        var r = GestureRecognizer(config: .defaults)
        // Drive into .clicking
        for i in 0..<3 { _ = r.step(pointingHand(t: Double(i)/30)) }
        _ = r.step(handWithIndexAngle(150, at: 0.5, y: 0.5, t: 3.0/30))
        for i in 4..<7 { _ = r.step(handWithIndexAngle(130, at: 0.5, y: 0.5, t: Double(i)/30)) }
        // Single frame above 155 → immediate release back to pointing
        let release = r.step(handWithIndexAngle(170, at: 0.5, y: 0.5, t: 7.0/30))
        if case .pointing = release {} else {
            XCTFail("Expected immediate .pointing on release")
        }
    }

    // Helper: build a pointing-style hand with a custom index-finger angle.
    func handWithIndexAngle(_ deg: Double, at x: Double = 0.5, y: Double = 0.5, t: Double = 0) -> HandObservation {
        let bend = max(min(deg, 180), 0)
        var hand = PoseClassifierTests().makeHand(indexBendDeg: bend, middleBendDeg: 60)
        hand.timestampSec = t
        let mcp = hand.points[.indexMCP]!
        let dx = x - mcp.x
        let dy = y - mcp.y
        for (k, p) in hand.points {
            hand.points[k] = NormalizedPoint(x: p.x + dx, y: p.y + dy, confidence: p.confidence)
        }
        return hand
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `swift test`
Expected: `GestureRecognizer` undefined.

- [ ] **Step 3: Implement `GestureRecognizer`**

`Sources/BurritoCursorCore/GestureRecognizer.swift`:

```swift
import Foundation

public final class GestureRecognizer {
    private let config: Config
    public private(set) var lastState: GestureState = .idle

    // Debounce buffer: per-frame classified pose + observation
    private struct Frame {
        let obs: HandObservation
        let pose: ClassifiedPose
    }
    private var window: [Frame] = []
    private let windowCapacity = 8

    // Continuity tracking — last MCP we accepted as "the hand"
    private var lastAcceptedMCP: NormalizedPoint?

    public init(config: Config) {
        self.config = config
    }

    public func step(_ obs: HandObservation) -> GestureState {
        // 1. Empty observation → idle (also clears MCP continuity)
        guard !obs.points.isEmpty else {
            lastAcceptedMCP = nil
            transition(to: .idle)
            return lastState
        }

        // 2. Confidence gate → degraded overlay
        if obs.minConfidence < config.degradedConfidenceThreshold {
            transitionToDegraded()
            return lastState
        }

        // 3. Hand-jump continuity check
        if let prev = lastAcceptedMCP, let cur = obs.points[.indexMCP] {
            let dx = cur.x - prev.x
            let dy = cur.y - prev.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist > config.handJumpRejectionFraction {
                lastAcceptedMCP = nil
                window.removeAll()
                transition(to: .idle)
                return lastState
            }
        }
        if let cur = obs.points[.indexMCP] {
            lastAcceptedMCP = cur
        }

        // 4. Classify pose, push into window
        let pose = PoseClassifier.classify(obs)
        window.append(Frame(obs: obs, pose: pose))
        if window.count > windowCapacity { window.removeFirst(window.count - windowCapacity) }

        // 5. State transition logic
        let newState = computeNextState(currentPose: pose, currentObs: obs)
        transition(to: newState)
        return lastState
    }

    private func computeNextState(currentPose pose: ClassifiedPose, currentObs obs: HandObservation) -> GestureState {
        let mcp = obs.points[.indexMCP] ?? NormalizedPoint(x: 0, y: 0, confidence: 0)
        let entryFrames = config.debounceEntryFrames

        // Immediate-release transitions from .clicking
        if case .clicking = lastState {
            if pose.indexAngleDeg > config.clickExitAngleDeg {
                return .pointing(point: mcp)
            }
            if pose.kind == .unknown {
                return .pointing(point: mcp) // forces InputCoordinator to emit mouseUp
            }
            return .clicking(point: mcp) // stay clicked while finger is bent
        }

        // From .clickLatched: confirm if angle < clickEnterAngle for N frames; release if > clickExit
        if case .clickLatched = lastState {
            if pose.indexAngleDeg > config.clickExitAngleDeg {
                return .pointing(point: mcp) // abandoned click
            }
            let sustainedBent = window.suffix(entryFrames).allSatisfy { $0.pose.indexAngleDeg < config.clickEnterAngleDeg }
            if window.suffix(entryFrames).count == entryFrames && sustainedBent {
                return .clicking(point: mcp)
            }
            return .clickLatched(point: mcp)
        }

        // From .pointing: maybe latch click, maybe scroll, maybe lose pose
        if case .pointing = lastState {
            if pose.indexAngleDeg < config.clickExitAngleDeg && pose.kind != .scrolling {
                return .clickLatched(point: mcp)
            }
            let recent = window.suffix(entryFrames)
            if recent.count == entryFrames && recent.allSatisfy({ $0.pose.kind == .scrolling }) {
                let dy = scrollDeltaY(from: recent)
                return .scrolling(deltaY: dy, point: mcp)
            }
            if pose.kind == .pointing {
                return .pointing(point: mcp)
            }
            return .idle
        }

        // From .scrolling: continue while pose stays scrolling
        if case .scrolling = lastState {
            if pose.kind == .scrolling {
                let recent = window.suffix(min(2, window.count))
                let dy = scrollDeltaY(from: recent)
                return .scrolling(deltaY: dy, point: mcp)
            }
            if pose.kind == .pointing {
                return .pointing(point: mcp)
            }
            return .idle
        }

        // From .idle / .degraded: need N sustained frames of pointing
        let recent = window.suffix(entryFrames)
        if recent.count == entryFrames && recent.allSatisfy({ $0.pose.kind == .pointing }) {
            return .pointing(point: mcp)
        }
        if recent.count == entryFrames && recent.allSatisfy({ $0.pose.kind == .scrolling }) {
            let dy = scrollDeltaY(from: recent)
            return .scrolling(deltaY: dy, point: mcp)
        }
        return .idle
    }

    private func scrollDeltaY(from frames: ArraySlice<Frame>) -> Double {
        guard frames.count >= 2,
              let first = frames.first?.obs.points[.indexMCP],
              let last = frames.last?.obs.points[.indexMCP] else { return 0 }
        return (last.y - first.y) * config.scrollSensitivity
    }

    private func transition(to next: GestureState) {
        lastState = next
    }

    private func transitionToDegraded() {
        let previous: GestureState.PreviousNonDegraded
        switch lastState {
        case .idle: previous = .idle
        case .pointing(let p): previous = .pointing(point: p)
        case .clickLatched(let p): previous = .clickLatched(point: p)
        case .clicking(let p): previous = .clicking(point: p)
        case .scrolling(_, let p): previous = .scrolling(point: p)
        case .degraded(let prev): previous = prev
        }
        lastState = .degraded(previous: previous)
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `swift test`
Expected: all 6 GestureRecognizer tests passing.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursorCore/GestureRecognizer.swift Tests/BurritoCursorCoreTests/GestureRecognizerTests.swift
git commit -m "Add GestureRecognizer state machine with debounce + hand-jump"
```

---

### Task 7: JSON-fixture trace replay tests

The recognizer is now testable. Bake in regression coverage by recording adversarial scenarios as JSON traces.

**Files:**
- Create: `Tests/BurritoCursorCoreTests/Fixtures/trace_clean_click.json`
- Create: `Tests/BurritoCursorCoreTests/Fixtures/trace_confidence_drop_mid_click.json`
- Create: `Tests/BurritoCursorCoreTests/Fixtures/trace_hand_swap.json`
- Create: `Tests/BurritoCursorCoreTests/TraceReplayTests.swift`

- [ ] **Step 1: Write the trace test (will fail without fixtures)**

`Tests/BurritoCursorCoreTests/TraceReplayTests.swift`:

```swift
import XCTest
@testable import BurritoCursorCore

final class TraceReplayTests: XCTestCase {
    func testCleanClickTrace() throws {
        let states = try replay("trace_clean_click")
        // Must contain at least one .pointing followed by at least one .clicking, then back to .pointing.
        let kinds = states.map { kindLabel($0) }
        XCTAssertTrue(kinds.contains("pointing"))
        XCTAssertTrue(kinds.contains("clicking"))
        let clickIdx = kinds.firstIndex(of: "clicking")!
        XCTAssertEqual(kinds[clickIdx + 1...].first(where: { $0 != "clicking" }), "pointing")
    }

    func testConfidenceDropMidClick() throws {
        let states = try replay("trace_confidence_drop_mid_click")
        let kinds = states.map { kindLabel($0) }
        XCTAssertTrue(kinds.contains("clicking"))
        XCTAssertTrue(kinds.contains("degraded"), "Mid-click confidence drop must enter .degraded")
    }

    func testHandSwap() throws {
        let states = try replay("trace_hand_swap")
        let kinds = states.map { kindLabel($0) }
        XCTAssertTrue(kinds.contains("idle"), "Hand jump must reset to idle")
    }

    // MARK: Helpers

    func replay(_ fixtureName: String) throws -> [GestureState] {
        let url = Bundle.module.url(forResource: fixtureName, withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let trace = try JSONDecoder().decode([HandObservation].self, from: data)
        let r = GestureRecognizer(config: .defaults)
        return trace.map { r.step($0) }
    }

    func kindLabel(_ s: GestureState) -> String {
        switch s {
        case .idle: return "idle"
        case .pointing: return "pointing"
        case .clickLatched: return "clickLatched"
        case .clicking: return "clicking"
        case .scrolling: return "scrolling"
        case .degraded: return "degraded"
        }
    }
}
```

- [ ] **Step 2: Update `Package.swift` to bundle the fixtures**

Edit `Package.swift` — change the test target line:

```swift
.testTarget(name: "BurritoCursorCoreTests", dependencies: ["BurritoCursorCore"], resources: [.copy("Fixtures")]),
```

- [ ] **Step 3: Write fixture `trace_clean_click.json`**

This should be a JSON array of 15 frames: 5 pointing, 1 latched (150°), 4 clicking (130°), 5 pointing again. Use this minimal generator script and save the output:

```bash
cat > /tmp/gen_fixtures.swift <<'SCRIPT'
import Foundation

struct Pt: Codable { var x: Double; var y: Double; var confidence: Double }
struct Obs: Codable { var timestampSec: Double; var points: [String: Pt] }

func finger(mcpX: Double, mcpY: Double, bendDeg: Double, conf: Double = 1.0) -> [String: Pt] {
    let mcp = Pt(x: mcpX, y: mcpY, confidence: conf)
    let pip = Pt(x: mcpX, y: mcpY + 0.05, confidence: conf)
    let angleRad = (180 - bendDeg) * .pi / 180
    let tipX = mcpX + 0.05 * sin(angleRad)
    let tipY = mcpY + 0.05 + 0.05 * cos(angleRad)
    let tip = Pt(x: tipX, y: tipY, confidence: conf)
    return ["MCP": mcp, "PIP": pip, "TIP": tip]
}

func frame(t: Double, indexBend: Double, conf: Double = 1.0) -> Obs {
    var pts: [String: Pt] = [:]
    let idx = finger(mcpX: 0.5, mcpY: 0.5, bendDeg: indexBend, conf: conf)
    pts["indexMCP"] = idx["MCP"]
    pts["indexPIP"] = idx["PIP"]
    pts["indexTip"] = idx["TIP"]
    let mid = finger(mcpX: 0.52, mcpY: 0.5, bendDeg: 60, conf: conf)
    pts["middleMCP"] = mid["MCP"]
    pts["middlePIP"] = mid["PIP"]
    pts["middleTip"] = mid["TIP"]
    let ring = finger(mcpX: 0.54, mcpY: 0.5, bendDeg: 60, conf: conf)
    pts["ringMCP"] = ring["MCP"]
    pts["ringPIP"] = ring["PIP"]
    pts["ringTip"] = ring["TIP"]
    let pinky = finger(mcpX: 0.56, mcpY: 0.5, bendDeg: 60, conf: conf)
    pts["pinkyMCP"] = pinky["MCP"]
    pts["pinkyPIP"] = pinky["PIP"]
    pts["pinkyTip"] = pinky["TIP"]
    pts["wrist"] = Pt(x: 0.53, y: 0.3, confidence: conf)
    return Obs(timestampSec: t, points: pts)
}

func write(_ frames: [Obs], to path: String) {
    let data = try! JSONEncoder().encode(frames)
    try! data.write(to: URL(fileURLWithPath: path))
}

// trace_clean_click: 5 pointing → 1 latched (150°) → 4 clicking (130°) → 5 pointing
var clean: [Obs] = []
for i in 0..<5 { clean.append(frame(t: Double(i)/30, indexBend: 180)) }
clean.append(frame(t: 5.0/30, indexBend: 150))
for i in 6..<10 { clean.append(frame(t: Double(i)/30, indexBend: 130)) }
for i in 10..<15 { clean.append(frame(t: Double(i)/30, indexBend: 180)) }
write(clean, to: "Tests/BurritoCursorCoreTests/Fixtures/trace_clean_click.json")

// trace_confidence_drop_mid_click: pointing → clicking → drop confidence
var drop: [Obs] = []
for i in 0..<5 { drop.append(frame(t: Double(i)/30, indexBend: 180)) }
drop.append(frame(t: 5.0/30, indexBend: 150))
for i in 6..<10 { drop.append(frame(t: Double(i)/30, indexBend: 130)) }
for i in 10..<13 { drop.append(frame(t: Double(i)/30, indexBend: 130, conf: 0.1)) }
write(drop, to: "Tests/BurritoCursorCoreTests/Fixtures/trace_confidence_drop_mid_click.json")

// trace_hand_swap: pointing at (0.5,0.5), then suddenly at (0.1,0.1)
var swap: [Obs] = []
for i in 0..<5 { swap.append(frame(t: Double(i)/30, indexBend: 180)) }
// frame 5: hand teleports
var jumped = frame(t: 5.0/30, indexBend: 180)
for (k, v) in jumped.points {
    jumped.points[k] = Pt(x: v.x - 0.4, y: v.y - 0.4, confidence: v.confidence)
}
swap.append(jumped)
for i in 6..<10 {
    var f = frame(t: Double(i)/30, indexBend: 180)
    for (k, v) in f.points {
        f.points[k] = Pt(x: v.x - 0.4, y: v.y - 0.4, confidence: v.confidence)
    }
    swap.append(f)
}
write(swap, to: "Tests/BurritoCursorCoreTests/Fixtures/trace_hand_swap.json")
print("OK")
SCRIPT
mkdir -p Tests/BurritoCursorCoreTests/Fixtures
swift /tmp/gen_fixtures.swift
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `swift test --filter TraceReplayTests`
Expected: 3 tests passing.

- [ ] **Step 5: Commit**

```bash
git add Tests/BurritoCursorCoreTests/TraceReplayTests.swift Tests/BurritoCursorCoreTests/Fixtures Package.swift
git commit -m "Add JSON-trace replay tests for recognizer"
```

---

## Phase 3 — I/O modules (manual testing required)

> **Note on testing from here:** Modules 8–13 touch `AVCaptureSession`, `VNDetectHumanHandPoseRequest`, and `CGEvent` — all of which require running on a real Mac with camera + Accessibility permissions. Unit tests cover what they can; the rest is manual UAT in Task 21.

### Task 8: `CameraPipeline`

**Files:**
- Create: `Sources/BurritoCursor/CameraPipeline.swift`

- [ ] **Step 1: Implement `CameraPipeline`**

```swift
import AVFoundation
import CoreVideo

final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "burritocursor.camera", qos: .userInitiated)
    private var handler: ((CVPixelBuffer, CMTime) -> Void)?

    func start(onFrame: @escaping (CVPixelBuffer, CMTime) -> Void) throws {
        self.handler = onFrame
        session.beginConfiguration()
        session.sessionPreset = .vga640x480 // low-res is fine for hand pose

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw NSError(domain: "BurritoCursor", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "BurritoCursor", code: 2)
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else {
            throw NSError(domain: "BurritoCursor", code: 3)
        }
        session.addOutput(videoOutput)

        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
        handler = nil
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        handler?(pb, t)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BurritoCursor/CameraPipeline.swift
git commit -m "Add CameraPipeline wrapping AVCaptureSession"
```

---

### Task 9: `HandPoseDetector` with backpressure

**Files:**
- Create: `Sources/BurritoCursor/HandPoseDetector.swift`

- [ ] **Step 1: Implement `HandPoseDetector`**

```swift
import Vision
import CoreVideo
import CoreMedia
import BurritoCursorCore

final class HandPoseDetector {
    private let request: VNDetectHumanHandPoseRequest
    private let processQueue = DispatchQueue(label: "burritocursor.vision", qos: .userInitiated)
    private var pendingBuffer: (CVPixelBuffer, CMTime)?
    private var isProcessing = false
    private let lock = NSLock()
    private var handler: ((HandObservation?) -> Void)?

    init() {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
    }

    func setHandler(_ h: @escaping (HandObservation?) -> Void) {
        handler = h
    }

    /// Submits a frame for processing. If the detector is busy, replaces the
    /// pending frame rather than queueing — guarantees latest-frame processing.
    func submit(buffer: CVPixelBuffer, timestamp: CMTime) {
        lock.lock()
        pendingBuffer = (buffer, timestamp)
        let shouldStart = !isProcessing
        if shouldStart { isProcessing = true }
        lock.unlock()
        if shouldStart { drain() }
    }

    private func drain() {
        processQueue.async { [weak self] in
            guard let self else { return }
            while true {
                self.lock.lock()
                guard let (buf, ts) = self.pendingBuffer else {
                    self.isProcessing = false
                    self.lock.unlock()
                    return
                }
                self.pendingBuffer = nil
                self.lock.unlock()

                let obs = self.runVision(on: buf, timestamp: ts)
                self.handler?(obs)
            }
        }
    }

    private func runVision(on buffer: CVPixelBuffer, timestamp: CMTime) -> HandObservation? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = (request.results ?? []).first else { return nil }
        return convert(observation: observation, timestamp: timestamp.seconds)
    }

    private func convert(observation: VNHumanHandPoseObservation, timestamp: Double) -> HandObservation? {
        var pts: [JointName: NormalizedPoint] = [:]
        let mapping: [(VNHumanHandPoseObservation.JointName, JointName)] = [
            (.wrist, .wrist),
            (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
            (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
            (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
            (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
            (.littleMCP, .pinkyMCP), (.littlePIP, .pinkyPIP), (.littleDIP, .pinkyDIP), (.littleTip, .pinkyTip),
        ]
        for (visionName, ourName) in mapping {
            if let p = try? observation.recognizedPoint(visionName), p.confidence > 0 {
                // Vision: bottom-left origin. Mirror x for selfie cam → "right in frame == right on screen"
                pts[ourName] = NormalizedPoint(x: 1.0 - p.location.x, y: p.location.y, confidence: Double(p.confidence))
            }
        }
        return HandObservation(timestampSec: timestamp, points: pts)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BurritoCursor/HandPoseDetector.swift
git commit -m "Add HandPoseDetector with latest-frame backpressure"
```

---

### Task 10: `InputCoordinator` — mouseDown/mouseUp safety

**Files:**
- Create: `Sources/BurritoCursor/InputCoordinator.swift`

- [ ] **Step 1: Implement `InputCoordinator`**

```swift
import AppKit
import CoreGraphics
import BurritoCursorCore

final class InputCoordinator {
    private var mouseDownOutstanding = false
    private let lock = NSLock()

    var cursorController: CursorController?
    var scrollController: ScrollController?

    func apply(state: GestureState) {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .idle, .degraded:
            forceReleaseLocked()
        case .pointing(let p):
            forceReleaseLocked()
            cursorController?.handlePointing(at: p)
        case .clickLatched(let p):
            forceReleaseLocked()
            cursorController?.freeze(at: p)
        case .clicking(let p):
            if !mouseDownOutstanding {
                cursorController?.mouseDown(at: p)
                mouseDownOutstanding = true
            }
        case .scrolling(let dy, _):
            forceReleaseLocked()
            scrollController?.scroll(deltaY: dy)
        }
    }

    /// Called from app-level lifecycle events (sleep, lid, quit, OFF toggle, permission loss).
    /// Always safe to call multiple times; idempotent.
    func forceRelease() {
        lock.lock()
        defer { lock.unlock() }
        forceReleaseLocked()
    }

    private func forceReleaseLocked() {
        if mouseDownOutstanding {
            cursorController?.mouseUp()
            mouseDownOutstanding = false
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: errors about `CursorController` and `ScrollController` undefined. Move to next task — they get defined there.

(No commit yet; we'll commit after the next two tasks compile together.)

---

### Task 11: `CursorController`

**Files:**
- Create: `Sources/BurritoCursor/CursorController.swift`

- [ ] **Step 1: Implement `CursorController`**

```swift
import AppKit
import CoreGraphics
import BurritoCursorCore

final class CursorController {
    private let config: Config
    private var oneEuroX: OneEuroFilter
    private var oneEuroY: OneEuroFilter
    private var lastMCP: NormalizedPoint?

    init(config: Config) {
        self.config = config
        self.oneEuroX = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
        self.oneEuroY = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
    }

    func handlePointing(at mcp: NormalizedPoint) {
        defer { lastMCP = mcp }
        guard let prev = lastMCP else { return }

        var dx = mcp.x - prev.x
        var dy = -(mcp.y - prev.y) // Vision y is bottom-left; macOS cursor y in CGEvent is top-left → flip

        // Deadzone
        if abs(dx) < config.deadzoneNormalized { dx = 0 }
        if abs(dy) < config.deadzoneNormalized { dy = 0 }

        // Sensitivity scaled to primary screen
        guard let screen = NSScreen.main else { return }
        let screenW = screen.frame.width
        let screenH = screen.frame.height

        let now = CACurrentMediaTime()
        let sx = oneEuroX.filter(dx * screenW * config.sensitivity / 0.2, timestampSec: now)
        let sy = oneEuroY.filter(dy * screenH * config.sensitivity / 0.2, timestampSec: now)

        let cur = currentCursorPosition()
        let target = CGPoint(x: cur.x + sx, y: cur.y + sy)
        post(eventType: .mouseMoved, at: target)
    }

    func freeze(at mcp: NormalizedPoint) {
        lastMCP = mcp
        // No-op for cursor movement. Reset the filter so next pointing frame is clean.
        oneEuroX = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
        oneEuroY = OneEuroFilter(minCutoff: config.oneEuroMinCutoff, beta: config.oneEuroBeta)
    }

    func mouseDown(at mcp: NormalizedPoint) {
        let cur = currentCursorPosition()
        post(eventType: .leftMouseDown, at: cur)
    }

    func mouseUp() {
        let cur = currentCursorPosition()
        post(eventType: .leftMouseUp, at: cur)
    }

    private func currentCursorPosition() -> CGPoint {
        // CGEventCreate returns event with current mouse location in Quartz coords (top-left origin).
        guard let evt = CGEvent(source: nil) else { return .zero }
        return evt.location
    }

    private func post(eventType: CGEventType, at p: CGPoint) {
        guard let evt = CGEvent(mouseEventSource: nil, mouseType: eventType,
                                mouseCursorPosition: p, mouseButton: .left) else { return }
        evt.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Verify build (still missing ScrollController)**

Run: `swift build`
Expected: only `ScrollController` undefined. Continue.

---

### Task 12: `ScrollController`

**Files:**
- Create: `Sources/BurritoCursor/ScrollController.swift`

- [ ] **Step 1: Implement `ScrollController`**

```swift
import CoreGraphics
import BurritoCursorCore

final class ScrollController {
    private let config: Config

    init(config: Config) {
        self.config = config
    }

    /// `deltaY` is normalized (frame fraction) per the recognizer. Convert to wheel units.
    func scroll(deltaY: Double) {
        // Convert normalized deltaY to wheel lines. Scaling factor below is empirical;
        // tune in bake testing.
        let lines = Int32((deltaY * 200).rounded())
        guard lines != 0 else { return }
        guard let evt = CGEvent(scrollWheelEvent2Source: nil,
                                units: .line,
                                wheelCount: 1,
                                wheel1: -lines,  // invert: hand moves down → page scrolls down
                                wheel2: 0,
                                wheel3: 0) else { return }
        evt.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit (InputCoordinator + CursorController + ScrollController together)**

```bash
git add Sources/BurritoCursor/InputCoordinator.swift Sources/BurritoCursor/CursorController.swift Sources/BurritoCursor/ScrollController.swift
git commit -m "Add InputCoordinator, CursorController, ScrollController"
```

---

## Phase 4 — App orchestration

### Task 13: `AppController` skeleton + menu bar item

**Files:**
- Create: `Sources/BurritoCursor/AppController.swift`
- Modify: `Sources/BurritoCursor/main.swift`

- [ ] **Step 1: Implement `AppController`**

```swift
import AppKit
import BurritoCursorCore

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isOn = false
    private var config: Config = Config.load(from: UserDefaults.standard)

    private var camera: CameraPipeline?
    private var detector: HandPoseDetector?
    private var recognizer: GestureRecognizer?
    private var coordinator: InputCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installSleepObserver()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.forceRelease()
        teardown()
    }

    // MARK: Menu bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "✋"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: isOn ? "Disable Cursor" : "Enable Cursor",
            action: #selector(toggle),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(NSMenuItem.separator())

        let hud = NSMenuItem(title: "Show Debug HUD", action: #selector(showDebugHUD), keyEquivalent: "")
        hud.target = self
        menu.addItem(hud)
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func toggle() {
        if isOn { teardown() } else { startup() }
        statusItem.menu = buildMenu()
        statusItem.button?.title = isOn ? "🤚" : "✋"
    }

    @objc private func showDebugHUD() {
        // Implemented in Task 18.
    }

    // MARK: Pipeline lifecycle

    private func startup() {
        guard checkPermissions() else { return }
        let cam = CameraPipeline()
        let det = HandPoseDetector()
        let rec = GestureRecognizer(config: config)
        let coord = InputCoordinator()
        coord.cursorController = CursorController(config: config)
        coord.scrollController = ScrollController(config: config)

        det.setHandler { [weak coord, weak rec] obs in
            guard let coord, let rec else { return }
            let state = rec.step(obs ?? HandObservation(timestampSec: 0, points: [:]))
            DispatchQueue.main.async { coord.apply(state: state) }
        }

        do {
            try cam.start { [weak det] buf, ts in
                det?.submit(buffer: buf, timestamp: ts)
            }
        } catch {
            NSLog("Camera failed: \(error)")
            return
        }

        self.camera = cam
        self.detector = det
        self.recognizer = rec
        self.coordinator = coord
        self.isOn = true
    }

    private func teardown() {
        coordinator?.forceRelease()
        camera?.stop()
        camera = nil
        detector = nil
        recognizer = nil
        coordinator = nil
        isOn = false
    }

    // MARK: Permissions (filled out in Task 14)

    private func checkPermissions() -> Bool {
        // Stub for now; Task 14 expands this.
        return true
    }

    // MARK: Sleep / lid close

    private func installSleepObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(onSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(onWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func onSleep() {
        coordinator?.forceRelease()
        if isOn { teardown(); statusItem.menu = buildMenu() }
    }

    @objc private func onWake() {
        // Re-check permissions on wake; do not auto-enable.
    }
}
```

- [ ] **Step 2: Replace `main.swift`**

```swift
import AppKit

let delegate = AppController()
NSApp.delegate = delegate
NSApp.run()
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: success.

- [ ] **Step 4: Smoke run from CLI (no .app bundle yet — Camera will be denied but menu bar should appear)**

Run: `swift run BurritoCursor`
Expected: a hand emoji appears in the menu bar. Click it → menu with "Enable Cursor" / "Show Debug HUD" / "Quit".
Quit the app with the menu item before continuing.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursor/AppController.swift Sources/BurritoCursor/main.swift
git commit -m "Add AppController with menu bar, sleep handling, on/off"
```

---

### Task 14: Permissions as runtime state

**Files:**
- Modify: `Sources/BurritoCursor/AppController.swift`

- [ ] **Step 1: Add permission helpers and runtime checks**

Replace the `checkPermissions` stub with:

```swift
private func checkPermissions() -> Bool {
    let camera = AVCaptureDevice.authorizationStatus(for: .video)
    let accessibility = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

    switch camera {
    case .authorized:
        break
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        return false
    default:
        showAlert(title: "Camera access denied",
                  message: "Grant Camera permission in System Settings → Privacy & Security → Camera, then re-enable.")
        return false
    }

    if !accessibility {
        showAlert(title: "Accessibility access required",
                  message: "Grant Accessibility permission in System Settings → Privacy & Security → Accessibility, then re-enable.")
        return false
    }
    return true
}

private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
```

- [ ] **Step 2: Add `import AVFoundation` at top of `AppController.swift`**

- [ ] **Step 3: Re-check on activation and wake**

In `applicationDidFinishLaunching`, after `installSleepObserver`, add:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(onActivation),
    name: NSApplication.didBecomeActiveNotification,
    object: nil)
```

And add:

```swift
@objc private func onActivation() {
    if isOn && !permissionsStillGranted() {
        teardown()
        statusItem.menu = buildMenu()
        showAlert(title: "Permission revoked", message: "Burrito Cursor has been disabled.")
    }
}

private func permissionsStillGranted() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .video) == .authorized &&
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
}
```

Update `onWake` to also call `permissionsStillGranted()` and tear down if revoked.

- [ ] **Step 4: Verify build**

Run: `swift build`
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursor/AppController.swift
git commit -m "Treat permissions as runtime state, tear down on revocation"
```

---

### Task 15: Global hotkey

**Files:**
- Modify: `Sources/BurritoCursor/AppController.swift`

- [ ] **Step 1: Register the hotkey**

Add `import KeyboardShortcuts` at top.

Inside the module (top level of file or in an extension), declare:

```swift
extension KeyboardShortcuts.Name {
    static let toggleBurritoCursor = Self("toggleBurritoCursor", default: .init(.h, modifiers: [.control, .option]))
}
```

Inside `applicationDidFinishLaunching`, after the activation observer:

```swift
KeyboardShortcuts.onKeyDown(for: .toggleBurritoCursor) { [weak self] in
    self?.toggle()
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BurritoCursor/AppController.swift
git commit -m "Add global hotkey ⌃⌥H via KeyboardShortcuts"
```

---

## Phase 5 — UX polish

### Task 16: First-run onboarding window

**Files:**
- Create: `Sources/BurritoCursor/OnboardingWindow.swift`
- Modify: `Sources/BurritoCursor/AppController.swift`

- [ ] **Step 1: Implement `OnboardingWindow`**

```swift
import AppKit
import AVFoundation
import Vision
import BurritoCursorCore

final class OnboardingWindow: NSWindowController {
    private let previewView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Waiting…")
    private let camera = CameraPipeline()
    private let detector = HandPoseDetector()

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "Burrito Cursor — Setup"
        win.center()
        self.init(window: win)
        installViews()
    }

    private func installViews() {
        guard let cv = window?.contentView else { return }
        previewView.frame = NSRect(x: 20, y: 60, width: 480, height: 280)
        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.cgColor
        cv.addSubview(previewView)

        statusLabel.frame = NSRect(x: 20, y: 20, width: 480, height: 24)
        statusLabel.alignment = .center
        cv.addSubview(statusLabel)
    }

    func startPreview() {
        detector.setHandler { [weak self] obs in
            DispatchQueue.main.async {
                if let obs, !obs.points.isEmpty {
                    let pose = PoseClassifier.classify(obs)
                    self?.statusLabel.stringValue = "Detected: \(pose.kind)  (idx=\(Int(pose.indexAngleDeg))°)"
                } else {
                    self?.statusLabel.stringValue = "No hand visible"
                }
            }
        }
        do {
            try camera.start { [weak self] buf, ts in
                self?.detector.submit(buffer: buf, timestamp: ts)
                if let img = OnboardingWindow.image(from: buf) {
                    DispatchQueue.main.async { self?.previewView.image = img }
                }
            }
        } catch {
            statusLabel.stringValue = "Camera error: \(error.localizedDescription)"
        }
    }

    private static func image(from pb: CVPixelBuffer) -> NSImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: ci.extent.width, height: ci.extent.height))
    }

    override func close() {
        camera.stop()
        super.close()
    }
}
```

- [ ] **Step 2: Trigger from menu bar**

In `AppController.buildMenu()`, replace the "Show Debug HUD" item with two items:

```swift
let onboard = NSMenuItem(title: "Onboarding…", action: #selector(showOnboarding), keyEquivalent: "")
onboard.target = self
menu.addItem(onboard)

let hud = NSMenuItem(title: "Show Debug HUD", action: #selector(showDebugHUD), keyEquivalent: "")
hud.target = self
menu.addItem(hud)
```

Add to `AppController`:

```swift
private var onboarding: OnboardingWindow?

@objc private func showOnboarding() {
    if onboarding == nil { onboarding = OnboardingWindow() }
    onboarding?.showWindow(nil)
    onboarding?.startPreview()
}
```

- [ ] **Step 3: Auto-open onboarding on first run**

Add to `applicationDidFinishLaunching`:

```swift
if !UserDefaults.standard.bool(forKey: "onboardingShown") {
    showOnboarding()
    UserDefaults.standard.set(true, forKey: "onboardingShown")
}
```

- [ ] **Step 4: Verify build**

Run: `swift build`
Expected: success.

- [ ] **Step 5: Commit**

```bash
git add Sources/BurritoCursor/OnboardingWindow.swift Sources/BurritoCursor/AppController.swift
git commit -m "Add first-run onboarding window with live hand preview"
```

---

### Task 17: Debug HUD overlay

**Files:**
- Create: `Sources/BurritoCursor/DebugHUD.swift`
- Modify: `Sources/BurritoCursor/AppController.swift`

- [ ] **Step 1: Implement `DebugHUD`**

```swift
import AppKit
import BurritoCursorCore

final class DebugHUD: NSWindowController {
    private let textView = NSTextView()
    private(set) var isShown = false

    convenience init() {
        let win = NSPanel(
            contentRect: NSRect(x: 40, y: 40, width: 320, height: 240),
            styleMask: [.titled, .closable, .hudWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        win.title = "Burrito Debug"
        win.level = .floating
        win.isFloatingPanel = true
        self.init(window: win)
        installViews()
    }

    private func installViews() {
        guard let cv = window?.contentView else { return }
        let scroll = NSScrollView(frame: cv.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = false
        textView.frame = scroll.bounds
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.backgroundColor = .clear
        scroll.documentView = textView
        cv.addSubview(scroll)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        isShown = true
    }

    override func close() {
        isShown = false
        super.close()
    }

    /// Called frequently with the latest pipeline snapshot.
    func update(state: GestureState, frameRateHz: Double, visionLatencyMs: Double, minConfidence: Double) {
        let stateLabel: String
        switch state {
        case .idle: stateLabel = "idle"
        case .pointing: stateLabel = "pointing"
        case .clickLatched: stateLabel = "clickLatched"
        case .clicking: stateLabel = "clicking"
        case .scrolling: stateLabel = "scrolling"
        case .degraded: stateLabel = "degraded"
        }
        let text = String(
            format: "state: %@\nfps: %.1f\nvision latency: %.1f ms\nmin landmark conf: %.2f",
            stateLabel, frameRateHz, visionLatencyMs, minConfidence
        )
        DispatchQueue.main.async { [textView] in
            textView.string = text
        }
    }
}
```

- [ ] **Step 2: Wire to `AppController`**

In `AppController` add:

```swift
private var hud: DebugHUD?

@objc private func showDebugHUD() {
    if hud == nil { hud = DebugHUD() }
    hud?.showWindow(nil)
}
```

In the detector handler (inside `startup()`), after computing `state`:

```swift
DispatchQueue.main.async {
    coord.apply(state: state)
    self.hud?.update(state: state, frameRateHz: 0, visionLatencyMs: 0, minConfidence: 0) // wired roughly
}
```

(Real frameRate/latency wiring is in the post-v1 deferred list — this gives a working surface for the state field, the most important debug signal.)

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add Sources/BurritoCursor/DebugHUD.swift Sources/BurritoCursor/AppController.swift
git commit -m "Add Debug HUD overlay window"
```

---

## Phase 6 — Packaging + UAT

### Task 18: `.app` bundle build script

**Files:**
- Create: `scripts/build_app.sh`

- [ ] **Step 1: Write the build script**

```bash
#!/bin/bash
set -euo pipefail

APP_NAME=BurritoCursor
DISPLAY_NAME="Burrito Cursor"
BUILD_DIR=.build/release
BUNDLE=$APP_NAME.app

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

echo "Built $BUNDLE"
echo "Run: open ./$BUNDLE"
echo "Or move to /Applications: mv $BUNDLE /Applications/"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/build_app.sh
```

- [ ] **Step 3: Build the app**

```bash
./scripts/build_app.sh
```

Expected: `BurritoCursor.app` directory created in repo root.

- [ ] **Step 4: Launch the bundled app**

```bash
open ./BurritoCursor.app
```

Expected: hand emoji appears in menu bar. macOS prompts for Camera permission on first enable; Accessibility prompt when toggled on.

- [ ] **Step 5: Commit**

```bash
git add scripts/build_app.sh
git commit -m "Add .app bundle build script"
```

---

### Task 19: Manual UAT bake test

**No code; this is a verification checklist. Record results in a new file `docs/superpowers/uat/2026-05-21-bake-test.md`.**

- [ ] **Step 1: Create UAT log file**

`docs/superpowers/uat/2026-05-21-bake-test.md`:

```markdown
# Burrito Cursor — v1 Bake Test Log

**Date:** 2026-05-21
**Build:** [commit SHA]
**macOS version:** [run `sw_vers`]

## Acceptance checks

- [ ] **Menu bar icon appears** on launch
- [ ] **Camera permission prompt** appears on first enable
- [ ] **Accessibility permission prompt** appears on first enable
- [ ] **Onboarding window shows live camera feed** with pose label updating in real time
- [ ] **Pointing pose moves cursor** in the expected direction (right hand right = cursor right)
- [ ] **Index finger bend produces a single click** on the element under the cursor
- [ ] **No cursor drift during click** (visible jump under 5px)
- [ ] **Click does not get stuck** — verify mouseUp fires by clicking and then dropping hand from view
- [ ] **Two-finger pose scrolls** in a web page
- [ ] **Scroll direction matches expectation** (hand moves down → page scrolls down)
- [ ] **Trackpad still works** while app is ON
- [ ] **Hotkey ⌃⌥H toggles** the app on/off
- [ ] **Lid close while ON** triggers graceful disable (no stuck cursor)
- [ ] **Permission revocation while ON** disables the app and shows the alert
- [ ] **Multi-hand intrusion** (wave another hand into frame) does not steal cursor mid-action
- [ ] **10-minute eating session** with a real burrito — note count of false clicks, abandoned scrolls, stuck states

## Tuning notes

Record any Config values you ended up changing during the bake test:

| Key | Default | Tuned to | Reason |
|---|---|---|---|
|   |   |   |   |

## Issues found

[bullet list]

## Verdict

- [ ] Ship v1 as is
- [ ] Block on [...]
```

- [ ] **Step 2: Run through the checklist**

Run the app via `open ./BurritoCursor.app`. Work through every box. Record results.

- [ ] **Step 3: Commit the filled-in log**

```bash
git add docs/superpowers/uat/2026-05-21-bake-test.md
git commit -m "Add v1 bake test UAT log"
```

---

## Self-review

**Spec coverage:**
- Problem / solution / use case → addressed implicitly (app exists)
- Locked decisions → all 8 implemented (air tap, MCP anchor, click+scroll, two-finger scroll, menu bar+hotkey, relative mapping, clutch via pose, Swift+Vision)
- Architecture diagram → Tasks 8–13 implement each pipeline stage
- 8 modules → Tasks 8 (CameraPipeline), 9 (HandPoseDetector), 6 (GestureRecognizer), 10 (InputCoordinator), 11 (CursorController), 12 (ScrollController), 13–15 (AppController), 17 (DebugHUD) — all covered
- State machine (idle/pointing/clickLatched/clicking/scrolling/degraded) → Task 6
- Asymmetric debounce, pre-threshold latch, mouseDown safety, hand-jump rejection, latest-frame processing → Tasks 6, 9, 10
- Cursor mapping math → Task 11
- Config layer → Task 2 (all 11 keys)
- Activation, hotkey, coexistence → Tasks 13, 15
- Permissions runtime state → Task 14
- First-run onboarding → Task 16
- Debug HUD → Task 17
- Testing strategy (unit + manual UAT) → Tasks 2, 3, 5, 6, 7 unit; Task 19 manual

**Placeholders:** None remaining. Tuning values for sensitivity and scroll scaling are explicit defaults in `Config` with bake-test tuning called out in Task 19.

**Type consistency:** `Config`, `GestureState`, `HandObservation`, `NormalizedPoint`, `JointName`, `ClassifiedPose` defined once and used consistently. `forceRelease()` / `apply(state:)` / `step(_:)` method names stable across tasks.

**Deferred items not in plan (intentional):** Palm-stabilized anchor, right-click/drag/double-click, multi-display, visual/audio click confirmation, Config UI, external webcam — all listed as post-v1 in the spec's Deferred section.
