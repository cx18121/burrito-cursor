import AppKit
import AVFoundation
import ApplicationServices

/// Camera + Accessibility (TCC) permission checks and revocation polling.
/// Stateless w/r/t the rest of the app — `AppController` queries it on the
/// fast path and installs a `Timer` for slow-path revocation detection.
enum PermissionsManager {
    enum Status {
        case granted
        case cameraNotDetermined   // prompt has been shown; user hasn't decided
        case cameraDenied
        case accessibilityMissing
    }

    /// Combined check. For `.cameraNotDetermined` the system prompt is
    /// triggered as a side effect of `AVCaptureDevice.requestAccess`. For
    /// `.accessibilityMissing` the system prompt is triggered via
    /// `AXIsProcessTrustedWithOptions(prompt: true)`.
    static func check() -> Status {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in /* user decides */ }
            return .cameraNotDetermined
        default:
            return .cameraDenied
        }

        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            return .accessibilityMissing
        }
        return .granted
    }

    /// Silent re-check used by revocation polling and on activation/wake.
    static func stillGranted() -> Bool {
        let cam = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let ax = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
        return cam && ax
    }
}

/// Wraps the revocation poll timer. macOS doesn't notify when permissions are
/// revoked while the app is running and focused, so we re-check periodically.
/// 60s interval — activation/wake handlers catch the common cases, so a slow
/// fallback is enough.
final class PermissionRevocationPoller {
    private var timer: Timer?
    private let interval: TimeInterval

    init(interval: TimeInterval = 60.0) {
        self.interval = interval
    }

    func start(onRevoked: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            if !PermissionsManager.stillGranted() { onRevoked() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
