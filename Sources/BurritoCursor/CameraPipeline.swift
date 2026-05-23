import AVFoundation
import CoreMedia
import CoreVideo

/// AVFoundation capture session — produces raw frames. Frames flow to any
/// number of subscribers (cursor, preview, debug overlay, …) via opaque
/// `UUID` tokens; there is no "main handler" vs "tap" distinction.
final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Target camera frame rate. Vision is already rate-capped to ~15fps; without
    /// this cap the camera delivers 30fps and AVFoundation does ~2× more work
    /// (ISP, pixel conversion, buffer churn) than Vision can consume.
    private static let targetFPS: Int32 = 15

    typealias FrameHandler = (CVPixelBuffer, CMTime) -> Void

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var sessionObserversInstalled = false

    /// Serial queue for ALL AVCaptureSession lifecycle ops.
    private let sessionQueue = DispatchQueue(label: "burritocursor.camera.session", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "burritocursor.camera.capture", qos: .userInitiated)

    private let lock = NSLock()
    private var subscribers: [UUID: FrameHandler] = [:]
    private var _errorHandler: ((Error?) -> Void)?

    // MARK: - Subscription

    /// Returns a token; pass it to `unsubscribe(_:)` to detach.
    func subscribe(_ handler: @escaping FrameHandler) -> UUID {
        let id = UUID()
        lock.lock(); subscribers[id] = handler; lock.unlock()
        return id
    }

    func unsubscribe(_ id: UUID) {
        lock.lock(); subscribers.removeValue(forKey: id); lock.unlock()
    }

    /// Called on AVCaptureSession runtime error or interruption.
    func setErrorHandler(_ h: @escaping (Error?) -> Void) {
        lock.lock(); _errorHandler = h; lock.unlock()
    }

    private func currentSubscribers() -> [FrameHandler] {
        lock.lock(); defer { lock.unlock() }
        return Array(subscribers.values)
    }

    private func currentErrorHandler() -> ((Error?) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return _errorHandler
    }

    // MARK: - Lifecycle

    func start() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw NSError(domain: "BurritoCursor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No camera device available"])
        }
        let input = try AVCaptureDeviceInput(device: device)

        // All session mutation + startRunning happens serially on sessionQueue.
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .vga640x480

            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                session.commitConfiguration()
                self.reportError(code: 2, message: "Cannot add camera input")
                return
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            // No `videoSettings`: Vision accepts the camera's native YUV directly;
            // forcing BGRA would mean ~1.2 MB/frame of needless CPU conversion.
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            } else {
                session.commitConfiguration()
                self.reportError(code: 3, message: "Cannot add video output")
                return
            }
            session.commitConfiguration()

            self.applyFrameRateCap(device: device)
            self.installSessionObservers()
            session.startRunning()
        }
    }

    func stop() {
        // Clear subscribers immediately so any in-flight frame is dropped.
        lock.lock()
        subscribers.removeAll()
        _errorHandler = nil
        lock.unlock()

        sessionQueue.async { [self] in
            if sessionObserversInstalled {
                NotificationCenter.default.removeObserver(self)
                sessionObserversInstalled = false
            }
            session.stopRunning()
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
        }
    }

    private func applyFrameRateCap(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            let dur = CMTime(value: 1, timescale: Self.targetFPS)
            let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
                CMTimeCompare(dur, $0.minFrameDuration) >= 0 &&
                CMTimeCompare(dur, $0.maxFrameDuration) <= 0
            }
            if supported {
                device.activeVideoMinFrameDuration = dur
                device.activeVideoMaxFrameDuration = dur
            } else {
                NSLog("BurritoCursor: camera active format does not support %dfps cap; staying at device default", Self.targetFPS)
            }
            device.unlockForConfiguration()
        } catch {
            NSLog("BurritoCursor: could not cap camera fps: %@", error.localizedDescription)
        }
    }

    private func reportError(code: Int, message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.currentErrorHandler()?(NSError(
                domain: "BurritoCursor", code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
        }
    }

    // MARK: - Session observers

    private func installSessionObservers() {
        guard !sessionObserversInstalled else { return }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onSessionRuntimeError(_:)),
                       name: .AVCaptureSessionRuntimeError, object: session)
        nc.addObserver(self, selector: #selector(onSessionInterrupted(_:)),
                       name: .AVCaptureSessionWasInterrupted, object: session)
        sessionObserversInstalled = true
    }

    @objc private func onSessionRuntimeError(_ note: Notification) {
        let err = note.userInfo?[AVCaptureSessionErrorKey] as? Error
        NSLog("BurritoCursor: capture session runtime error: %@", err?.localizedDescription ?? "unknown")
        DispatchQueue.main.async { [weak self] in self?.currentErrorHandler()?(err) }
    }

    @objc private func onSessionInterrupted(_ note: Notification) {
        NSLog("BurritoCursor: capture session interrupted")
        DispatchQueue.main.async { [weak self] in self?.currentErrorHandler()?(nil) }
    }

    // MARK: - Delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        for handler in currentSubscribers() {
            handler(pb, t)
        }
    }
}
