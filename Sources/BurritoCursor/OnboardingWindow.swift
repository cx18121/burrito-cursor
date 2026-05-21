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
    private let camera = CameraPipeline()
    private let detector = HandPoseDetector()
    private let ciContext = CIContext()

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
        detector.setHandler { [weak self] obs in
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
            try camera.start { [weak self] buf, ts in
                self?.detector.submit(buffer: buf, timestamp: ts)
                self?.updatePreview(buf)
            }
        } catch {
            statusLabel.stringValue = "Camera error: \(error.localizedDescription)"
        }
    }

    private func updatePreview(_ pb: CVPixelBuffer) {
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        let img = NSImage(cgImage: cg, size: NSSize(width: ci.extent.width, height: ci.extent.height))
        DispatchQueue.main.async { [weak self] in
            self?.previewView.image = img
        }
    }

    override func close() {
        camera.stop()
        super.close()
    }
}
