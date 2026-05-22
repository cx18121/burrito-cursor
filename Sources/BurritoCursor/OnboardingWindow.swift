import AppKit
import AVFoundation
import CoreImage
import CoreVideo
import Vision
import BurritoCursorCore

final class OnboardingWindow: NSWindowController {
    private let previewView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Waiting for camera…")
    private let instructionsLabel = NSTextField(wrappingLabelWithString: """
        Point your index finger at the screen with other fingers curled.
        Bend your index finger to click. Extend index + middle for scroll.
        """)
    private var camera: CameraPipeline?
    private var detector: HandPoseDetector?
    private let ciContext = CIContext()

    /// Most recent observation, used to overlay landmarks on the preview.
    /// Lock-guarded — written from capture queue, read on main during draw.
    private var latestObservation: HandObservation?
    private let observationLock = NSLock()

    /// Wall-clock of the last preview render. Used to throttle preview rendering
    /// to ~15fps — full 30fps was the source of severe slowdown (NSImage lockFocus
    /// + bitmap composition on the main thread is expensive on retina displays).
    /// Hand pose detection still runs at full camera rate; only the preview throttles.
    private var lastPreviewRenderTime: Double = 0
    private let previewMinFrameIntervalSec: Double = 1.0 / 15.0

    /// Lock-guarded "have we seen at least one frame" flag. Written from the
    /// camera capture queue; read from main when the window closes.
    private var _capturedAtLeastOneFrame = false
    /// True once we've received at least one camera frame. AppController reads
    /// this to decide whether to mark first-run as complete.
    var capturedAtLeastOneFrame: Bool {
        observationLock.lock(); defer { observationLock.unlock() }
        return _capturedAtLeastOneFrame
    }

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

    func startPreview() {
        // Always rebuild — CameraPipeline / HandPoseDetector are not designed
        // for restart on the same instance.
        stopPreview()
        let cam = CameraPipeline()
        let det = HandPoseDetector()
        det.setHandler { [weak self] obs, _ in
            self?.observationLock.lock()
            self?.latestObservation = obs
            self?.observationLock.unlock()
            DispatchQueue.main.async {
                if let obs, !obs.points.isEmpty {
                    let pose = PoseClassifier.classify(obs)
                    self?.statusLabel.stringValue = String(
                        format: "%@ — index %d° middle %d° conf %.2f",
                        String(describing: pose.kind),
                        Int(pose.indexAngleDeg),
                        Int(pose.middleAngleDeg),
                        obs.minConfidence
                    )
                } else {
                    self?.statusLabel.stringValue = "No hand visible"
                }
            }
        }
        do {
            try cam.start { [weak self] buf, ts in
                guard let self else { return }
                self.observationLock.lock()
                self._capturedAtLeastOneFrame = true
                self.observationLock.unlock()
                det.submit(buffer: buf, timestamp: ts)
                self.updatePreview(buf)
            }
            self.camera = cam
            self.detector = det
        } catch {
            statusLabel.stringValue = "Camera error: \(error.localizedDescription)"
        }
    }

    private func stopPreview() {
        camera?.stop()
        camera = nil
        detector = nil
    }

    private func updatePreview(_ pb: CVPixelBuffer) {
        // Throttle preview rendering to ~15fps. Detection still runs at full rate.
        let now = CACurrentMediaTime()
        if now - lastPreviewRenderTime < previewMinFrameIntervalSec { return }
        lastPreviewRenderTime = now

        // CoreImage extraction is thread-safe; do it off-main.
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let w = Int(ci.extent.width)
        let h = Int(ci.extent.height)

        observationLock.lock()
        let obs = latestObservation
        observationLock.unlock()

        // Build the composed image off-main using a direct CGContext bitmap.
        // This avoids NSImage(size:) + lockFocus allocation overhead — that
        // pattern was the source of the slowness on retina displays.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let obs, !obs.points.isEmpty {
            OnboardingWindow.drawLandmarks(obs, into: ctx, width: w, height: h)
        }
        guard let finalCG = ctx.makeImage() else { return }
        let composed = NSImage(cgImage: finalCG, size: NSSize(width: w, height: h))

        DispatchQueue.main.async { [weak self] in
            self?.previewView.image = composed
        }
    }

    /// Draws hand landmarks directly into a CGContext (faster than NSBezierPath).
    /// Coords are un-mirrored to match the camera image.
    private static func drawLandmarks(
        _ obs: HandObservation, into ctx: CGContext, width: Int, height: Int
    ) {
        let dotRadius: CGFloat = 4
        let lineWidth: CGFloat = 2

        func cgPoint(_ p: BurritoCursorCore.NormalizedPoint) -> CGPoint {
            CGPoint(x: (1.0 - p.x) * Double(width), y: p.y * Double(height))
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
                guard let p = obs.points[j] else { continue }
                let sp = cgPoint(p)
                if didMove { ctx.addLine(to: sp) } else { ctx.move(to: sp); didMove = true }
            }
            ctx.strokePath()
        }
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        for (_, p) in obs.points {
            let sp = cgPoint(p)
            ctx.fillEllipse(in: CGRect(
                x: sp.x - dotRadius, y: sp.y - dotRadius,
                width: dotRadius * 2, height: dotRadius * 2
            ))
        }
    }

    override func close() {
        stopPreview()
        super.close()
    }
}
