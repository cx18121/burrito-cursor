import AVFoundation
import CoreVideo

final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Serial queue for ALL AVCaptureSession lifecycle ops (begin/commit configuration,
    /// add/remove inputs/outputs, startRunning, stopRunning). Prevents races on
    /// rapid toggle and onboarding-restart paths.
    private let sessionQueue = DispatchQueue(label: "burritocursor.camera.session", qos: .userInitiated)

    /// Capture delegate queue (frame callbacks land here).
    private let captureQueue = DispatchQueue(label: "burritocursor.camera.capture", qos: .userInitiated)

    private let lock = NSLock()
    private var _handler: ((CVPixelBuffer, CMTime) -> Void)?
    private var _errorHandler: ((Error?) -> Void)?

    /// Called on AVCaptureSession runtime error or interruption.
    func setErrorHandler(_ h: @escaping (Error?) -> Void) {
        lock.lock(); _errorHandler = h; lock.unlock()
    }

    private func currentHandler() -> ((CVPixelBuffer, CMTime) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return _handler
    }

    private func currentErrorHandler() -> ((Error?) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return _errorHandler
    }

    func start(onFrame: @escaping (CVPixelBuffer, CMTime) -> Void) throws {
        // Synchronous validation — fail fast if camera is missing.
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw NSError(domain: "BurritoCursor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No camera device available"])
        }
        let input = try AVCaptureDeviceInput(device: device)

        lock.lock(); _handler = onFrame; lock.unlock()

        // All session mutation + startRunning happens serially on sessionQueue.
        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .vga640x480

            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                session.commitConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.currentErrorHandler()?(NSError(
                        domain: "BurritoCursor", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"]
                    ))
                }
                return
            }

            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            } else {
                session.commitConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.currentErrorHandler()?(NSError(
                        domain: "BurritoCursor", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"]
                    ))
                }
                return
            }
            session.commitConfiguration()

            self.installSessionObservers()
            session.startRunning()
        }
    }

    func stop() {
        // Clear handlers immediately so any in-flight capture frame is dropped.
        lock.lock(); _handler = nil; _errorHandler = nil; lock.unlock()

        sessionQueue.async { [self] in
            NotificationCenter.default.removeObserver(self)
            session.stopRunning()
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
        }
    }

    private func installSessionObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self, selector: #selector(onSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError, object: session
        )
        nc.addObserver(
            self, selector: #selector(onSessionInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted, object: session
        )
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

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        currentHandler()?(pb, t)
    }
}
