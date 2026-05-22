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
        // CoreImage is thread-safe; do the GPU extraction off-main.
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let baseSize = NSSize(width: ci.extent.width, height: ci.extent.height)

        observationLock.lock()
        let obs = latestObservation
        observationLock.unlock()

        // AppKit drawing (lockFocus, NSBezierPath, NSColor) MUST run on main.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let baseImage = NSImage(cgImage: cg, size: baseSize)
            let composed = NSImage(size: baseSize)
            composed.lockFocus()
            baseImage.draw(in: NSRect(origin: .zero, size: baseSize))
            if let obs, !obs.points.isEmpty {
                OnboardingWindow.drawLandmarks(obs, in: baseSize)
            }
            composed.unlockFocus()
            self.previewView.image = composed
        }
    }

    /// Draws hand landmarks as colored dots + finger skeleton lines onto the current
    /// graphics context. Coordinates are mirrored back from screen-orientation
    /// (HandObservation's x is pre-mirrored) so they line up with the camera image.
    private static func drawLandmarks(_ obs: HandObservation, in size: NSSize) {
        let dotRadius: CGFloat = 4
        let lineWidth: CGFloat = 2

        func toScreen(_ p: BurritoCursorCore.NormalizedPoint) -> NSPoint {
            // HandObservation mirrors x; un-mirror to get camera-image coords.
            NSPoint(x: (1.0 - p.x) * Double(size.width), y: p.y * Double(size.height))
        }

        // Finger skeleton: MCP → PIP → DIP → Tip for each finger
        let fingers: [(NSColor, [JointName])] = [
            (.systemRed,    [.thumbCMC, .thumbMP, .thumbIP, .thumbTip]),
            (.systemOrange, [.indexMCP, .indexPIP, .indexDIP, .indexTip]),
            (.systemYellow, [.middleMCP, .middlePIP, .middleDIP, .middleTip]),
            (.systemGreen,  [.ringMCP, .ringPIP, .ringDIP, .ringTip]),
            (.systemBlue,   [.pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip]),
        ]
        for (color, joints) in fingers {
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            var didMove = false
            for j in joints {
                guard let p = obs.points[j] else { continue }
                let sp = toScreen(p)
                if didMove { path.line(to: sp) } else { path.move(to: sp); didMove = true }
            }
            color.withAlphaComponent(0.8).setStroke()
            path.stroke()
        }

        // Dots for every joint (including wrist)
        for (_, p) in obs.points {
            let sp = toScreen(p)
            let rect = NSRect(x: sp.x - dotRadius, y: sp.y - dotRadius,
                              width: dotRadius * 2, height: dotRadius * 2)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    override func close() {
        stopPreview()
        super.close()
    }
}
