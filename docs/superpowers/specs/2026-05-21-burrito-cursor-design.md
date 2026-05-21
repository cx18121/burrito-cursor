# Burrito-cursor — Design Spec

**Date:** 2026-05-21
**Status:** Draft for review (v2, post-Codex)
**Name:** burrito-cursor (repo, codename, and app display name)

## Problem

When your hands are messy (eating a burrito, sandwich, bagel; cooking; holding a baby; doing dishes), you can't touch the keyboard or trackpad. You still want basic control of your Mac — scroll a YouTube video, click play/pause, advance an article, switch tabs.

## Solution

A native macOS menu bar app that uses the built-in webcam to detect hand pose via Apple's Vision framework and translates a small gesture vocabulary into mouse and scroll events at the system level. Toggle on/off via menu bar icon or global hotkey.

## Use case

Daily, 5–30 minute sessions, enabled before the user picks up food, disabled after. Single-user, single Mac, personal use.

## Non-goals

- Always-on gesture recognition without an explicit enable toggle
- Full mouse parity (no right-click, drag, double-click in v1)
- Custom gestures or in-app configuration UI (config via `UserDefaults` only)
- Cross-platform (macOS only)
- Distribution beyond a personal `.app` bundle (no codesigning/notarization)
- Pinch click, voice activation, dwell click (explicitly rejected)

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Click mechanism | Air tap — index finger bend at MCP joint | Distinct from food handling, low false-trigger rate, well-proven (HoloLens) |
| Cursor anchor | MCP knuckle (landmark 5), not fingertip | Fingertip moves during click flexion; MCP barely does |
| Action set v1 | Click + scroll only | Covers ~80% of "while eating" needs (browsing, video, reading) |
| Scroll gesture | Index + middle extended, vertical hand motion | Mirrors trackpad muscle memory |
| Activation | Menu bar toggle + global hotkey | Explicit on/off state; user can't accidentally activate |
| Cursor mapping | Relative (delta-based) with clutch | Avoids "gorilla arm" fatigue from absolute mapping |
| Clutch mechanism | Drop the pointing pose; cursor freezes; reposition; resume | Pairs with gesture vocabulary — no extra gesture needed |
| Platform | Swift + Vision (`VNDetectHumanHandPoseRequest`) + AppKit + CGEvent | Native, low CPU/battery, single `.app` bundle |

## Architecture

```
[AVCaptureSession]
       ↓ pixel buffers (drop-oldest queue)
[HandPoseDetector] — wraps VNDetectHumanHandPoseRequest
       ↓ HandObservation? (landmarks + per-point confidence + timestamp)
[GestureRecognizer] — pure function over sliding window
       ↓ GestureState
[InputCoordinator] — single owner of synthetic input state
       ↓
[CursorController] (CGEvent mouse) + [ScrollController] (CGEvent scrollWheel)
```

The pipeline runs only when toggled ON. OFF releases the camera, idles at ~0% CPU.

## Modules

| Module | Responsibility | Key invariant |
|---|---|---|
| `CameraPipeline` | Owns `AVCaptureSession`, vends `CVPixelBuffer`s | Knows nothing about hands |
| `HandPoseDetector` | Wraps `VNDetectHumanHandPoseRequest`; sets `maximumHandCount = 1` | Knows nothing about gestures |
| `GestureRecognizer` | Pure function: `[HandObservation] → GestureState` | No I/O, no time-side-effects, fully unit-testable |
| `InputCoordinator` | Owns the synthetic-input state. Guarantees balanced `mouseDown`/`mouseUp` | Forces `mouseUp` on any abnormal exit |
| `CursorController` | Turns `GestureState` deltas into `CGEvent` mouse moves; owns deadzone, sensitivity, One Euro filter | All math is deterministic per input |
| `ScrollController` | Turns `GestureState` deltas into `CGEventCreateScrollWheelEvent` calls | Same |
| `AppController` | Menu bar UI, hotkey registration, permission state, on/off lifecycle | Treats permissions as live runtime state, not one-time |
| `DebugHUD` | Toggleable overlay window with pipeline diagnostics | Off by default; opt-in via hidden menu |

The split exists so `GestureRecognizer` can be tested without launching a camera.

## Gesture state machine

```
       ┌──────────────────────────────────┐
       │              .idle               │
       │  (no hand / unrecognized pose)   │
       └──────────────────────────────────┘
         ▲                          │
         │ confidence drop          │ index extended,
         │ or pose lost             │ pointing at screen,
         │                          │ debounce 3 frames
         │                          ▼
       ┌──────────────────────────────────┐
       │           .pointing(point)       │
       │       (knuckle delta → cursor)   │
       └──────────────────────────────────┘
         │       │                  │
         │       │ index angle      │ index + middle
         │       │ < 155° (latch)   │ extended, debounce
         │       ▼                  │ 3 frames
         │  ┌──────────────────┐    ▼
         │  │   .clickLatched  │  ┌────────────────────┐
         │  │  (cursor frozen, │  │   .scrolling(Δy)   │
         │  │   awaiting       │  │  (knuckle Δy →     │
         │  │   confirmation)  │  │   scroll events)   │
         │  └──────────────────┘  └────────────────────┘
         │       │
         │       │ angle < 140°,
         │       │ debounce 3 frames
         │       ▼
         │  ┌──────────────────┐
         │  │    .clicking     │  ──── on angle > 155°
         │  │  (mouseDown sent)│       OR confidence loss
         │  └──────────────────┘       OR hand lost:
         │       │                     fire mouseUp,
         │       │                     return to .pointing
         │       │
         └───────┘

.degraded — overlay state. Entered from any non-idle state when
landmark confidence falls below threshold. Behavior: hold last
cursor position, suppress new click/scroll events. Exit when
confidence recovers.
```

### Critical rules

1. **Asymmetric debounce.** Pose entry requires 3 consecutive frames (~100ms at 30fps). Pose exit on confidence loss is *immediate* (1 frame). This keeps click release feeling crisp while keeping entries stable.
2. **Pre-threshold click latch.** Cursor freezes at 155° (entering `.clickLatched`) before the click is confirmed at 140°. Prevents cursor drift during the finger-bend window.
3. **Mouse-down safety.** `InputCoordinator` tracks one bit: "is a synthetic mouseDown currently outstanding?" Any path that could break the click pairing — hand lost, confidence dropped, app toggled OFF, sleep/lid event, permission revoked, app termination via SIGINT/SIGTERM — fires `mouseUp` before transitioning.
4. **Hand identity continuity.** With `maximumHandCount = 1`, if the detected MCP position jumps more than ~25% of frame width between frames, treat it as a new hand: drop to `.idle` and require fresh acquisition.
5. **Latest-frame processing.** Vision requests run on a serial dispatch queue with a single-slot inbox. New frames replace pending ones rather than queueing. Cursor velocity stays even under inference latency spikes.

## Cursor mapping math

Per frame, while in `.pointing`:

1. Read landmark 5 (MCP of index) in normalized frame coords `(x, y) ∈ [0,1]`.
2. Compute `Δ = current − previous`, mirroring x (selfie camera).
3. Zero `Δ` components whose magnitude is below `deadzone` (default 0.005 of frame width).
4. Multiply by `sensitivity` (default tuned so ~20cm of arm sweep spans the primary display).
5. Pass through One Euro filter (`β = 0.007`, `mincutoff = 1.0`).
6. Read current cursor location via `NSEvent.mouseLocation`, add filtered delta, post `CGEventCreateMouseEvent(.mouseMoved, …)`.
7. On exit from `.pointing` (any cause), retain current cursor position. This is the clutch — no extra gesture needed.

Coordinate handling: webcam frames are mirrored at the detector layer so that "right-in-frame" maps to "right-on-screen." Primary display only in v1.

## Configuration

A single `Config` struct loaded from `UserDefaults` at startup. All tunable parameters live here, not as literals in code:

```swift
struct Config {
    var sensitivity: Double          // default 1.0
    var deadzoneNormalized: Double   // default 0.005
    var debounceEntryFrames: Int     // default 3
    var debounceExitFrames: Int      // default 1
    var clickEnterAngleDeg: Double   // default 140
    var clickExitAngleDeg: Double    // default 155
    var degradedConfidenceThreshold: Double  // default 0.3
    var handJumpRejectionFraction: Double    // default 0.25
    var hotkey: KeyCombo             // default ⌃⌥H
    var scrollSensitivity: Double    // default 1.0
    var oneEuroBeta: Double          // default 0.007
    var oneEuroMinCutoff: Double     // default 1.0
}
```

No in-app UI for editing in v1. Power users edit via `defaults write`.

## Activation, hotkey, coexistence

- **Menu bar icon** (`NSStatusItem`) with a hand glyph; click toggles on/off; right-click shows quit and "Show Debug HUD" items.
- **Global hotkey** via `KeyboardShortcuts` Swift package; default `⌃⌥H`; configurable in `Config`.
- **When OFF:** camera released, pipeline torn down, ~0% CPU.
- **When ON:** trackpad and physical mouse keep working — `CGEvent` is additive at the system level.
- **Auto-off triggers:** lid close (`NSWorkspace.willSleepNotification`), system sleep, screen lock. All routed through `InputCoordinator` to guarantee a forced `mouseUp` first.

## Permissions

Two are required:

| Permission | Mechanism | Failure behavior |
|---|---|---|
| Camera | `NSCameraUsageDescription` in `Info.plist` + `AVCaptureDevice.requestAccess` | If denied: menu bar icon shows red dot, click opens System Settings → Privacy → Camera |
| Accessibility | `AXIsProcessTrustedWithOptions(prompt: true)` | If denied: same red-dot behavior pointing to Accessibility |

Permissions are **runtime state**, not one-time setup. `AppController` re-checks both:
- On every app activation (`NSApplicationDidBecomeActiveNotification`)
- On every wake from sleep
- When the user clicks "enable" but state is unknown

If either permission is revoked while ON, the app gracefully disables and surfaces a banner.

## First-run onboarding

A single window that walks through:
1. **Permission prompts** — Camera, then Accessibility.
2. **Live hand-detection preview** — webcam feed with overlaid landmarks and detected pose label. User confirms "it sees my hand" before enabling cursor control.
3. **Quick gesture demo** — animated GIFs of the three poses (point, scroll, click) with one-line captions.
4. **Hotkey setup** — accept default or rebind.

Window dismisses itself on completion. Re-accessible via menu bar → "Onboarding…"

## Observability — Debug HUD

A floating, transparent overlay window (off by default). Shows in real time:

- Frame rate (camera in, Vision out, recognizer)
- Vision inference latency (last + rolling p95)
- Detected landmark count + min confidence
- Current `GestureState` + last transition reason
- Emitted CGEvents (mouse move/click/scroll, with timestamps)
- Active `Config` values

Toggleable from menu bar (right-click → "Show Debug HUD"). Pure read-only — no input controls.

Rationale: gesture-system bugs are otherwise pure guesswork. Build this in week one.

## Testing strategy

**Unit tests:**
- `GestureRecognizer`: feed recorded `[HandObservation]` traces (JSON fixtures), assert state transition sequence. Cover happy paths and adversarial inputs (confidence drops mid-click, hand jumps, ambiguous poses).
- `OneEuroFilter`: standard property tests for monotonicity and convergence.
- `CursorController` math: deterministic input → deterministic delta.

**Integration / manual UAT:**
- Bake test: use the app while eating a 10-minute meal. Success = no stuck clicks, no accidental clicks, scroll usable, no abandonment.
- Permission revocation: revoke each permission mid-session, verify graceful disable + correct UI.
- Sleep/wake cycle: trigger sleep mid-click, assert mouseUp fires.
- Multi-hand-in-frame: verify continuity logic rejects the wrong hand.

## Deferred (post-v1)

- **Palm-stabilized anchor.** Blend MCP with wrist/palm geometry for more stable cursor positioning. Only pursue if v1 jitter is intolerable on real targeting tasks — measure first.
- **Right-click, drag, double-click.** Action set "B" from brainstorming. Pursue once v1 click + scroll is reliable.
- **Multi-display support.** v1 restricts cursor to primary display.
- **Visual/audio click confirmation.** Possibly a faint system sound on click. Add only if users report unclear feedback.
- **Config UI.** A small Settings window. Power users can use `defaults write` for now.
- **External webcam support.** v1 uses default device.

## Open questions

1. **Onboarding hand-detection preview** — does the live preview need to record/replay so the user can see *themselves* not seeing themselves, or is "live mirror with landmarks" sufficient? Probably the latter; flag for UAT.
2. **Default sensitivity** — needs empirical tuning. Start with the value above, expect to adjust during bake testing.

## Spec self-review (inline)

- **Placeholders:** None. All defaults specified.
- **Internal consistency:** Module list, state machine, and architecture diagram all reference `InputCoordinator` consistently. Asymmetric debounce values (3 entry / 1 exit) match between state machine and Config. ✓
- **Scope:** Single-implementation-plan-sized. State machine and 8 modules. ✓
- **Ambiguity:** Hand-jump threshold uses "frame width" as the unit consistently; "primary display only" stated explicitly; "additive" CGEvent behavior with trackpad called out. ✓
