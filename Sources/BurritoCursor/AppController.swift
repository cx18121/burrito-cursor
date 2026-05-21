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

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installSleepObserver()
        installActivationObserver()
        installHotkey()
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
        statusItem.button?.title = isOn ? "🤚" : "✋"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let toggleTitle = isOn ? "Disable Cursor" : "Enable Cursor"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        let hudItem = NSMenuItem(title: "Show Debug HUD", action: #selector(showDebugHUD), keyEquivalent: "")
        hudItem.target = self
        menu.addItem(hudItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }

    @objc private func toggle() {
        if isOn { teardown() } else { startup() }
        refreshStatusItem()
    }

    @objc private func showDebugHUD() {
        // Wired up in Task 17.
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

        det.setHandler { [weak coord, weak rec] obs in
            guard let coord, let rec else { return }
            let state = rec.step(obs ?? HandObservation(timestampSec: 0, points: [:]))
            DispatchQueue.main.async { coord.apply(state: state) }
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
    }

    private func teardown() {
        coordinator?.forceRelease()
        camera?.stop()
        camera = nil
        detector = nil
        recognizer = nil
        coordinator = nil
        isOn = false
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

    // MARK: UI helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
