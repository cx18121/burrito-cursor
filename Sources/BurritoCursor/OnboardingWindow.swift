import AppKit
import CoreImage
import CoreVideo
import BurritoCursorCore

/// Live camera preview + status line + landmark overlay. Owns no camera or
/// detector — `AppController` feeds it `handleFrame` + `handleSnapshot` while
/// the window is open, then unsubscribes on close. This makes the preview
/// architecturally identical whether the cursor is also running or not.
final class OnboardingWindow: NSWindowController {
    private let previewView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Waiting for camera…")
    private let instructionsLabel = NSTextField(wrappingLabelWithString: """
        Point your index finger at the screen with other fingers curled.
        Pinch thumb + index to click. Open palm to scroll.
        """)
    private let ciContext = CIContext()

    /// Most recent observation, used to overlay landmarks on the preview.
    /// Lock-guarded — written from the snapshot-dispatch path, read on main
    /// during draw. We hold the landmarks (not the whole snapshot) because
    /// rendering only needs the point map.
    private var latestPoints: [JointName: NormalizedPoint]?
    private let observationLock = NSLock()

    /// Throttle preview rendering to ~15fps. Hand pose detection still runs at
    /// the camera's full rate; only the preview render path throttles.
    private var lastPreviewRenderTime: Double = 0
    private let previewMinFrameIntervalSec: Double = 1.0 / 15.0

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Burrito Cursor — Setup"
        win.center()
        win.isReleasedWhenClosed = false
        self.init(window: win)
        installViews()
    }

    private func installViews() {
        guard let cv = window?.contentView else { return }
        cv.wantsLayer = true

        previewView.frame = NSRect(x: 20, y: 110, width: 520, height: 300)
        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.cgColor
        previewView.layer?.cornerRadius = 8
        cv.addSubview(previewView)

        statusLabel.frame = NSRect(x: 20, y: 70, width: 520, height: 24)
        statusLabel.alignment = .center
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cv.addSubview(statusLabel)

        instructionsLabel.frame = NSRect(x: 20, y: 10, width: 520, height: 50)
        instructionsLabel.alignment = .center
        instructionsLabel.textColor = .secondaryLabelColor
        cv.addSubview(instructionsLabel)
    }

    // MARK: - Fed by AppController

    /// Frame callback from the upstream pipeline. Throttled internally.
    func handleFrame(_ pb: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        if now - lastPreviewRenderTime < previewMinFrameIntervalSec { return }
        lastPreviewRenderTime = now

        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let w = Int(ci.extent.width), h = Int(ci.extent.height)

        observationLock.lock()
        let points = latestPoints
        observationLock.unlock()

        // Compose camera + landmarks via a direct CGContext bitmap.
        // (NSImage(size:) + lockFocus has too much allocation overhead on retina.)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // Selfie mirror — HandObservation.x is pre-mirrored to match user-relative
        // space, so flipping the camera here makes landmarks line up at p.x * width.
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
        if let points, !points.isEmpty {
            Self.drawLandmarks(points, into: ctx, width: w, height: h)
        }
        guard let finalCG = ctx.makeImage() else { return }
        let composed = NSImage(cgImage: finalCG, size: NSSize(width: w, height: h))

        DispatchQueue.main.async { [weak self] in
            self?.previewView.image = composed
        }
    }

    /// Snapshot callback from the upstream pipeline. Updates the status line
    /// and stashes the landmark map for the next frame's overlay draw.
    func handleSnapshot(_ s: PipelineSnapshot) {
        observationLock.lock()
        latestPoints = s.observation?.points
        observationLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let pose = s.pose {
                self.statusLabel.stringValue = String(
                    format: "%@ — index %d° middle %d° conf %.2f pinch %.2f",
                    String(describing: pose.kind),
                    Int(pose.indexAngleDeg),
                    Int(pose.middleAngleDeg),
                    s.minConfidence,
                    pose.pinchDistance
                )
            } else {
                self.statusLabel.stringValue = "No hand visible"
            }
        }
    }

    /// Shown when the cursor pipeline is paused and no frames are flowing.
    func showPaused() {
        observationLock.lock(); latestPoints = nil; observationLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.stringValue = "Camera paused"
        }
    }

    // MARK: - Landmark drawing

    private static func drawLandmarks(
        _ points: [JointName: NormalizedPoint], into ctx: CGContext, width: Int, height: Int
    ) {
        let dotRadius: CGFloat = 4
        let lineWidth: CGFloat = 2

        func cgPoint(_ p: NormalizedPoint) -> CGPoint {
            CGPoint(x: p.x * Double(width), y: p.y * Double(height))
        }

        let fingers: [(CGColor, [JointName])] = [
            (NSColor.systemRed.withAlphaComponent(0.8).cgColor,    [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]),
            (NSColor.systemOrange.withAlphaComponent(0.8).cgColor, [.indexMCP, .indexPIP, .indexDIP, .indexTip]),
            (NSColor.systemYellow.withAlphaComponent(0.8).cgColor, [.middleMCP, .middlePIP, .middleDIP, .middleTip]),
            (NSColor.systemGreen.withAlphaComponent(0.8).cgColor,  [.ringMCP, .ringPIP, .ringDIP, .ringTip]),
            (NSColor.systemBlue.withAlphaComponent(0.8).cgColor,   [.pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip]),
        ]
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        for (color, joints) in fingers {
            ctx.setStrokeColor(color)
            var didMove = false
            ctx.beginPath()
            for j in joints {
                guard let p = points[j] else { continue }
                let sp = cgPoint(p)
                if didMove { ctx.addLine(to: sp) } else { ctx.move(to: sp); didMove = true }
            }
            ctx.strokePath()
        }
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        for (_, p) in points {
            let sp = cgPoint(p)
            ctx.fillEllipse(in: CGRect(
                x: sp.x - dotRadius, y: sp.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            ))
        }
    }
}
