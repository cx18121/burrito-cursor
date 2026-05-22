# 🌯 Burrito Cursor

Control your Mac cursor with hand gestures via the webcam — for when your hands are messy from eating, cooking, or otherwise occupied.

A native macOS menu bar app. Toggle it on, point at the screen, click by bending your index finger, scroll with two fingers. Your trackpad still works normally — gesture input is additive.

> **Status:** v0.1 — works end-to-end with `swift test` green and a runnable `.app` bundle. Pre-bake-test; sensitivity and click feel are still tuning targets.

---

## Gestures

| Gesture | Action |
|---|---|
| Index finger extended, others curled, pointing at screen | Move cursor (uses knuckle position, not fingertip — avoids click-time drift) |
| Bend index finger (HoloLens-style "air tap") | Click |
| Index + middle fingers extended | Scroll (vertical hand motion) |
| Drop the pointing pose | Cursor freezes — natural "clutch" so you can reposition your hand |

## Build & run

Requirements: macOS 13+, Xcode CLT (`xcode-select --install`), Swift 5.9+.

```bash
./scripts/build_app.sh
```

Builds, packages into `~/Applications/BurritoCursor.app`, re-registers with LaunchServices so Raycast/Spotlight find it immediately, and symlinks the bundle in the repo root for convenience.

Launch with `open ~/Applications/BurritoCursor.app` or via Raycast / Spotlight ("burrito cursor"). First launch opens a setup window with a live camera preview overlaying detected hand landmarks — confirm it sees your hand before enabling cursor control.

Click the 🌯 menu bar icon → **Enable Cursor**, or press `⌃⌥H`.

## Permissions

The app requires two macOS permissions, granted on first use:

- **Camera** — for webcam hand-pose detection (via Apple's Vision framework, on-device, no network)
- **Accessibility** — for synthesizing mouse and scroll events at the system level

If either gets revoked while the app is running, it disables itself within 10 seconds and surfaces a banner.

## Architecture

Two Swift Package targets:

- **`BurritoCursorCore`** — pure logic, no AppKit/Vision/CGEvent dependency. Unit-tested with XCTest. Contains `Config`, `OneEuroFilter`, `HandObservation`, `JointName`, `GestureState`, `PoseClassifier`, `GestureRecognizer`, `CursorMath`.
- **`BurritoCursor`** — executable target, macOS-specific. Contains `CameraPipeline` (AVCaptureSession on a dedicated serial queue), `HandPoseDetector` (Vision with latest-frame backpressure), `InputCoordinator` (guarantees balanced mouseDown/mouseUp), `CursorController`, `ScrollController`, `AppController`, `OnboardingWindow`, `DebugHUD`.

Pipeline: `AVCaptureSession → VNDetectHumanHandPoseRequest → GestureRecognizer (pure) → InputCoordinator → CursorController / ScrollController (CGEvent)`.

Full design spec at [`docs/superpowers/specs/2026-05-21-burrito-cursor-design.md`](docs/superpowers/specs/2026-05-21-burrito-cursor-design.md). Implementation plan and review-cycle history under [`docs/superpowers/`](docs/superpowers/).

## Configuration

All tunable parameters live in `Config` and load from `UserDefaults`. Adjust via:

```bash
defaults write com.charliexue.burritocursor sensitivity -float 1.5
defaults write com.charliexue.burritocursor scrollSensitivity -float 2.0
defaults write com.charliexue.burritocursor oneEuroBeta -float 0.01
```

Tunable keys: `sensitivity`, `scrollSensitivity`, `deadzoneNormalized`, `debounceEntryFrames`, `debounceExitFrames`, `clickEnterAngleDeg`, `clickExitAngleDeg`, `degradedConfidenceThreshold`, `handJumpRejectionFraction`, `oneEuroBeta`, `oneEuroMinCutoff`. All bounded — invalid values fall back to defaults.

## Tests

```bash
swift test
```

36 unit tests covering `Config`, `OneEuroFilter`, `PoseClassifier`, `GestureRecognizer` state machine, `CursorMath`, and JSON trace-replay regression fixtures (clean click, mid-click confidence drop, hand swap).

I/O modules (Camera, Vision, CGEvent) require real hardware and are verified manually — see [`docs/superpowers/uat/`](docs/superpowers/uat/) for the bake-test checklist.

## Roadmap

- v1: tune defaults from real bake-test feedback, add right-click + drag + double-click
- v2: palm-stabilized cursor anchor (blend MCP with wrist for stability under hand pitch/roll), multi-display support
- Later: configurable gestures, in-app settings UI, smooth scroll feel parity with trackpad

---

Built with deliberate review cycles — see commit history for the spec → plan → execute → multi-pass-review flow.
