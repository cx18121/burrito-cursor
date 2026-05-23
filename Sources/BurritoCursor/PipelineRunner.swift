import CoreVideo
import BurritoCursorCore

/// Owns the full per-frame pipeline (camera → detector → recognizer) and
/// exposes two subscriber streams:
///   - `subscribeFrame` — raw `CVPixelBuffer`, for rendering (preview window)
///   - `subscribeSnapshot` — fully-composed `PipelineSnapshot`, for state-driven
///     consumers (cursor input coordinator, debug HUD, preview status line)
///
/// One instance lives as long as anyone needs frames. `AppController` creates
/// it on the first consumer attaching and tears it down when the last detaches.
final class PipelineRunner {
    typealias FrameHandler = (CVPixelBuffer) -> Void
    typealias SnapshotHandler = (PipelineSnapshot) -> Void

    let camera = CameraPipeline()
    let detector = HandPoseDetector()
    let recognizer: GestureRecognizer
    let config: Config

    private var frameSubscribers: [UUID: FrameHandler] = [:]
    private var snapshotSubscribers: [UUID: SnapshotHandler] = [:]
    private let lock = NSLock()

    /// Subscriptions internal to the runner that wire camera → detector and
    /// detector → snapshot dispatch. Cancelled at `stop()`.
    private var detectorFeedSub: UUID?
    private var frameFanoutSub: UUID?
    private var snapshotProduceSub: UUID?

    init(config: Config) {
        self.config = config
        self.recognizer = GestureRecognizer(config: config)
    }

    // MARK: - Lifecycle

    func start() throws {
        // Camera → Detector (feeds Vision)
        detectorFeedSub = camera.subscribe { [weak detector] buf, ts in
            detector?.submit(buffer: buf, timestamp: ts)
        }
        // Camera → frame subscribers (for rendering)
        frameFanoutSub = camera.subscribe { [weak self] buf, _ in
            self?.fanoutFrame(buf)
        }
        // Detector → snapshot dispatch
        snapshotProduceSub = detector.subscribe { [weak self] obs, stats in
            self?.handleObservation(obs, stats)
        }

        try camera.start()
    }

    func setErrorHandler(_ h: @escaping (Error?) -> Void) {
        camera.setErrorHandler(h)
    }

    func stop() {
        // Tear down internal wiring before the camera so no late frames slip through.
        if let s = detectorFeedSub { camera.unsubscribe(s) }
        if let s = frameFanoutSub { camera.unsubscribe(s) }
        if let s = snapshotProduceSub { detector.unsubscribe(s) }
        detectorFeedSub = nil
        frameFanoutSub = nil
        snapshotProduceSub = nil
        camera.stop()
        lock.lock()
        frameSubscribers.removeAll()
        snapshotSubscribers.removeAll()
        lock.unlock()
    }

    // MARK: - Public subscription API

    func subscribeFrame(_ handler: @escaping FrameHandler) -> UUID {
        let id = UUID()
        lock.lock(); frameSubscribers[id] = handler; lock.unlock()
        return id
    }

    func subscribeSnapshot(_ handler: @escaping SnapshotHandler) -> UUID {
        let id = UUID()
        lock.lock(); snapshotSubscribers[id] = handler; lock.unlock()
        return id
    }

    func unsubscribe(_ id: UUID) {
        lock.lock()
        frameSubscribers.removeValue(forKey: id)
        snapshotSubscribers.removeValue(forKey: id)
        lock.unlock()
    }

    var hasAnyConsumer: Bool {
        lock.lock(); defer { lock.unlock() }
        return !frameSubscribers.isEmpty || !snapshotSubscribers.isEmpty
    }

    // MARK: - Internal dispatch

    private func fanoutFrame(_ buf: CVPixelBuffer) {
        lock.lock()
        let handlers = Array(frameSubscribers.values)
        lock.unlock()
        for h in handlers { h(buf) }
    }

    private func handleObservation(_ obs: HandObservation?, _ stats: DetectorStats) {
        let state = recognizer.step(obs ?? HandObservation(timestampSec: 0, points: [:]))
        let snapshot = PipelineSnapshot(
            state: state,
            pose: recognizer.lastPose,
            observation: obs,
            frameRateHz: stats.frameRateHz,
            visionLatencyMs: stats.visionLatencyMs
        )
        lock.lock()
        let handlers = Array(snapshotSubscribers.values)
        lock.unlock()
        for h in handlers { h(snapshot) }
    }
}
