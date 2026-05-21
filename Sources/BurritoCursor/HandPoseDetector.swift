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
