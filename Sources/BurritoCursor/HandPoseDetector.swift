import Vision
import CoreVideo
import CoreMedia
import QuartzCore
import BurritoCursorCore

/// Rolling pipeline stats — read every frame to populate the Debug HUD.
struct DetectorStats {
    var frameRateHz: Double = 0
    var visionLatencyMs: Double = 0
}

final class HandPoseDetector {
    private let request: VNDetectHumanHandPoseRequest
    private let processQueue = DispatchQueue(label: "burritocursor.vision", qos: .userInitiated)
    private var pendingBuffer: (CVPixelBuffer, CMTime)?
    private var isProcessing = false
    private let lock = NSLock()
    private var _handler: ((HandObservation?, DetectorStats) -> Void)?

    // Stats tracking — exponential moving average so the HUD reads smooth.
    private var lastFrameTime: CFTimeInterval?
    private var fpsEMA: Double = 0
    private var latencyEMA: Double = 0

    /// Vision rate cap. Hand tracking at 15fps is plenty for cursor control
    /// and roughly halves CPU vs unthrottled. Without this on slower hardware
    /// the app can saturate a core.
    private let minVisionIntervalSec: Double = 1.0 / 15.0
    private var lastVisionTime: CFTimeInterval = 0

    init() {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
    }

    func setHandler(_ h: @escaping (HandObservation?, DetectorStats) -> Void) {
        lock.lock(); defer { lock.unlock() }
        _handler = h
    }

    private func currentHandler() -> ((HandObservation?, DetectorStats) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return _handler
    }

    /// Submit a frame for processing. If the detector is busy, the new frame replaces
    /// the pending one — guarantees latest-frame processing under inference latency.
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

                // Rate-cap: skip this frame if we processed one too recently.
                // Without the cap, on slower hardware Vision can saturate a CPU core.
                let now = CACurrentMediaTime()
                if now - self.lastVisionTime < self.minVisionIntervalSec {
                    continue
                }
                self.lastVisionTime = now

                let visionStart = CACurrentMediaTime()
                let obs = self.runVision(on: buf, timestamp: ts)
                let visionElapsedMs = (CACurrentMediaTime() - visionStart) * 1000

                let frameTime = CACurrentMediaTime()
                if let prev = self.lastFrameTime {
                    let inst = 1.0 / max(frameTime - prev, 1e-6)
                    self.fpsEMA = self.fpsEMA == 0 ? inst : (0.9 * self.fpsEMA + 0.1 * inst)
                }
                self.lastFrameTime = frameTime
                self.latencyEMA = self.latencyEMA == 0
                    ? visionElapsedMs
                    : (0.9 * self.latencyEMA + 0.1 * visionElapsedMs)

                let stats = DetectorStats(frameRateHz: self.fpsEMA, visionLatencyMs: self.latencyEMA)
                self.currentHandler()?(obs, stats)
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
        var pts: [JointName: BurritoCursorCore.NormalizedPoint] = [:]
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
                // Mirror x for selfie camera: right-in-frame becomes right-on-screen.
                pts[ourName] = BurritoCursorCore.NormalizedPoint(
                    x: 1.0 - Double(p.location.x),
                    y: Double(p.location.y),
                    confidence: Double(p.confidence)
                )
            }
        }
        return HandObservation(timestampSec: timestamp, points: pts)
    }
}
