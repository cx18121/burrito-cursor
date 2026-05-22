import AVFoundation
import CoreVideo

final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "burritocursor.camera", qos: .userInitiated)
    private var handler: ((CVPixelBuffer, CMTime) -> Void)?
    private var errorHandler: ((Error?) -> Void)?

    /// Called on any AVCaptureSession runtime error or interruption. AppController
    /// uses this to tear down promptly instead of silently dropping frames.
    func setErrorHandler(_ h: @escaping (Error?) -> Void) {
        errorHandler = h
    }

    func start(onFrame: @escaping (CVPixelBuffer, CMTime) -> Void) throws {
        self.handler = onFrame
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard let device = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            throw NSError(domain: "BurritoCursor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No camera device available"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "BurritoCursor", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw NSError(domain: "BurritoCursor", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        session.addOutput(videoOutput)

        session.commitConfiguration()

        installSessionObservers()

        // startRunning blocks while the camera spins up — push off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
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
        DispatchQueue.main.async { [weak self] in self?.errorHandler?(err) }
    }

    @objc private func onSessionInterrupted(_ note: Notification) {
        NSLog("BurritoCursor: capture session interrupted")
        DispatchQueue.main.async { [weak self] in self?.errorHandler?(nil) }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        // Tear down on a background queue too; stopRunning can block briefly.
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
        }
        handler = nil
        errorHandler = nil
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        handler?(pb, t)
    }
}
