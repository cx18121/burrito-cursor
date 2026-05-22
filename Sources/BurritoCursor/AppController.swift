import AppKit
import AVFoundation
import ApplicationServices
import KeyboardShortcuts
import BurritoCursorCore

extension KeyboardShortcuts.Name {
    static let toggleBurritoCursor = Self(
        "toggleBurritoCursor",
        default: .init(.h, modifiers: [.control, .option])
    )
}

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isOn = false
    private var config: Config = Config.load(from: UserDefaults.standard)

    private var camera: CameraPipeline?
    private var detector: HandPoseDetector?
    private var recognizer: GestureRecognizer?
    private var coordinator: InputCoordinator?
    private var onboarding: OnboardingWindow?
    private var hud: DebugHUD?
    private var signalSources: [DispatchSourceSignal] = []
    private var permissionPollTimer: Timer?

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installSleepObserver()
        installActivationObserver()
        installSignalHandlers()
        installHotkey()

        if !UserDefaults.standard.bool(forKey: "onboardingShown") {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.forceRelease()
        teardown()
    }

    // MARK: Menu bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        guard let btn = statusItem.button else { return }
        // Burrito emoji as the menu bar icon, on brand. State is communicated by:
        // (1) the system's appearsDisabled rendering (faded when off, solid when on),
        // (2) the menu header dot (🟢 / ⚪️),
        // (3) the menu's "Enable / Disable Cursor" toggle label.
        btn.image = nil
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16)
        ]
        btn.attributedTitle = NSAttributedString(string: "🌯", attributes: attrs)
        btn.appearsDisabled = !isOn
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Status header — disabled item that visually communicates current state.
        let dot = isOn ? "🟢" : "⚪️"
        let header = NSMenuItem(title: "\(dot)  \(isOn ? "Cursor enabled" : "Cursor disabled")", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        // Toggle — show the global hotkey hint inline so users learn it
        let toggleTitle = isOn ? "Disable Cursor" : "Enable Cursor"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggle), keyEquivalent: "h")
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        toggleItem.target = self
        toggleItem.image = symbol(isOn ? "pause.circle" : "play.circle")
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        let onboardItem = NSMenuItem(title: "Setup & Camera Preview…", action: #selector(showOnboarding), keyEquivalent: "")
        onboardItem.target = self
        onboardItem.image = symbol("camera.viewfinder")
        menu.addItem(onboardItem)

        let hudItem = NSMenuItem(title: "Show Debug HUD", action: #selector(showDebugHUD), keyEquivalent: "")
        hudItem.target = self
        hudItem.image = symbol("chart.bar.doc.horizontal")
        menu.addItem(hudItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Burrito Cursor", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quitItem.image = symbol("power")
        menu.addItem(quitItem)

        return menu
    }

    /// Small SF Symbol image sized for menu rows.
    private func symbol(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }

    @objc private func toggle() {
        if isOn { teardown() } else { startup() }
        refreshStatusItem()
    }

    @objc private func showOnboarding() {
        // Onboarding opens its own camera session. To avoid two AVCaptureSessions
        // fighting over the camera, tear the main pipeline down while onboarding shows.
        if isOn { teardown(); refreshStatusItem() }
        if onboarding == nil { onboarding = OnboardingWindow() }
        onboarding?.showWindow(nil)
        onboarding?.window?.makeKeyAndOrderFront(nil)
        // Observe window close so we can persist onboardingShown only on success.
        if let win = onboarding?.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(onOnboardingClosed),
                name: NSWindow.willCloseNotification, object: win
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        onboarding?.startPreview()
    }

    @objc private func onOnboardingClosed(_ note: Notification) {
        defer {
            if let win = onboarding?.window {
                NotificationCenter.default.removeObserver(
                    self, name: NSWindow.willCloseNotification, object: win
                )
            }
        }
        // Only mark onboarding done if the user actually saw the camera working.
        // Otherwise they should be re-prompted on next launch.
        if onboarding?.capturedAtLeastOneFrame == true {
            UserDefaults.standard.set(true, forKey: "onboardingShown")
        }
    }

    @objc private func showDebugHUD() {
        if hud == nil { hud = DebugHUD() }
        hud?.showWindow(nil)
    }

    // MARK: Pipeline lifecycle

    private func startup() {
        guard checkPermissions() else { return }
        let cam = CameraPipeline()
        let det = HandPoseDetector()
        let rec = GestureRecognizer(config: config)
        let coord = InputCoordinator()
        coord.cursorController = CursorController(config: config)
        coord.scrollController = ScrollController(config: config)

        let cfg = config
        det.setHandler { [weak self, weak coord, weak rec] obs, stats in
            guard let coord, let rec else { return }
            let state = rec.step(obs ?? HandObservation(timestampSec: 0, points: [:]))
            let conf = obs?.minConfidence ?? 0.0
            let landmarks = obs?.points.count ?? 0
            let rawPose: ClassifiedPose?
            if let obs, !obs.points.isEmpty {
                rawPose = PoseClassifier.classify(obs)
            } else {
                rawPose = nil
            }
            DispatchQueue.main.async {
                coord.apply(state: state)
                self?.hud?.update(
                    state: state,
                    frameRateHz: stats.frameRateHz,
                    visionLatencyMs: stats.visionLatencyMs,
                    minConfidence: conf,
                    landmarkCount: landmarks,
                    rawPose: rawPose,
                    config: cfg
                )
            }
        }

        cam.setErrorHandler { [weak self] error in
            guard let self else { return }
            self.teardown()
            self.refreshStatusItem()
            self.showAlert(
                title: "Camera interrupted",
                message: error?.localizedDescription
                    ?? "The camera session was interrupted — Burrito Cursor has been disabled."
            )
        }
        do {
            try cam.start { [weak det] buf, ts in
                det?.submit(buffer: buf, timestamp: ts)
            }
        } catch {
            NSLog("BurritoCursor: camera failed to start: \(error)")
            showAlert(title: "Camera failed to start",
                      message: error.localizedDescription)
            return
        }

        self.camera = cam
        self.detector = det
        self.recognizer = rec
        self.coordinator = coord
        self.isOn = true
        startPermissionPolling()
    }

    private func teardown() {
        stopPermissionPolling()
        coordinator?.forceRelease()
        camera?.stop()
        camera = nil
        detector = nil
        recognizer = nil
        coordinator = nil
        isOn = false
    }

    /// While the app is enabled, poll TCC every 10 seconds. macOS doesn't notify
    /// when permissions are revoked, so polling is the only way to catch a mid-session
    /// revocation. 10s is cheap (just an API call) and bounds the user's surprise.
    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isOn && !self.permissionsStillGranted() {
                self.teardown()
                self.refreshStatusItem()
                self.showAlert(
                    title: "Permission revoked",
                    message: "Burrito Cursor has been disabled because Camera or Accessibility access is no longer granted."
                )
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    // MARK: Permissions

    private func checkPermissions() -> Bool {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraStatus {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                // User decides; they'll need to click Enable again after granting.
            }
            return false
        default:
            showAlert(
                title: "Camera access denied",
                message: "Grant Camera permission in System Settings → Privacy & Security → Camera, then re-enable."
            )
            return false
        }

        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            showAlert(
                title: "Accessibility access required",
                message: "Grant Accessibility permission in System Settings → Privacy & Security → Accessibility, then re-enable."
            )
            return false
        }
        return true
    }

    private func permissionsStillGranted() -> Bool {
        let cam = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let ax = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
        return cam && ax
    }

    // MARK: Lifecycle observers

    private func installSleepObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(onSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(onWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func installActivationObserver() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(onActivation),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func onSleep() {
        coordinator?.forceRelease()
        if isOn { teardown(); refreshStatusItem() }
    }

    @objc private func onWake() {
        if isOn && !permissionsStillGranted() {
            teardown()
            refreshStatusItem()
            showAlert(title: "Permission revoked",
                      message: "Burrito Cursor has been disabled because Camera or Accessibility access is no longer granted.")
        }
    }

    @objc private func onActivation() {
        if isOn && !permissionsStillGranted() {
            teardown()
            refreshStatusItem()
            showAlert(title: "Permission revoked",
                      message: "Burrito Cursor has been disabled because Camera or Accessibility access is no longer granted.")
        }
    }

    // MARK: Hotkey

    private func installHotkey() {
        KeyboardShortcuts.onKeyDown(for: .toggleBurritoCursor) { [weak self] in
            self?.toggle()
        }
    }

    // MARK: Signal handlers

    /// Catch SIGINT/SIGTERM and force-release any pending synthetic input before exiting.
    /// applicationWillTerminate does not fire on these signals (it's NSApplication-only),
    /// so without this a `kill` mid-click leaves a stuck mouseDown in the OS.
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN) // prevent default termination; dispatch source handles it
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.coordinator?.forceRelease()
                NSApp.terminate(nil)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    // MARK: UI helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
