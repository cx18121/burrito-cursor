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

/// App orchestration. Owns the menu bar item, lifecycle observers, and the
/// reference-counted `PipelineRunner`. Each user-facing capability (cursor,
/// camera preview, debug HUD) is a *consumer* that subscribes to the pipeline;
/// the pipeline runs while any consumer is attached and stops when the last
/// detaches.
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let config = Config.load(from: UserDefaults.standard)

    /// Pipeline is non-nil iff at least one consumer is attached.
    private var pipeline: PipelineRunner?

    // Cursor consumer
    private var isCursorOn = false
    private var cursorCoord: InputCoordinator?
    private var cursorSub: UUID?

    // Preview consumer
    private var onboarding: OnboardingWindow?
    private var previewFrameSub: UUID?
    private var previewSnapshotSub: UUID?
    private var previewSawFrame = false

    // HUD consumer
    private var hud: DebugHUD?
    private var hudSub: UUID?

    // Lifecycle infrastructure
    private var signalSources: [DispatchSourceSignal] = []
    private let revocationPoller = PermissionRevocationPoller()

    // MARK: - NSApplicationDelegate

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
        cursorCoord?.forceRelease()
        disableCursor()
        detachPreview()
        detachHUD()
        pipeline?.stop()
        pipeline = nil
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        guard let btn = statusItem.button else { return }
        btn.image = nil
        btn.attributedTitle = NSAttributedString(
            string: "🌯",
            attributes: [.font: NSFont.systemFont(ofSize: 16)]
        )
        btn.appearsDisabled = !isCursorOn
        statusItem.menu = MenuBuilder.build(
            state: .init(isCursorOn: isCursorOn),
            target: self,
            actions: .init(
                toggle: #selector(toggle),
                showPreview: #selector(showOnboarding),
                showHUD: #selector(showDebugHUD)
            )
        )
    }

    @objc private func toggle() {
        if isCursorOn { disableCursor() } else { enableCursor() }
        refreshStatusItem()
    }

    // MARK: - Pipeline lifecycle (reference-counted by consumers)

    /// Lazily start the pipeline if no consumer has it running yet. Wires any
    /// already-visible optional consumers (HUD) so the first consumer doesn't
    /// "steal" the live data feed from a HUD that was opened first.
    private func ensurePipelineStarted() -> PipelineRunner? {
        if let p = pipeline { return p }
        let p = PipelineRunner(config: config)
        p.setErrorHandler { [weak self] err in
            DispatchQueue.main.async { self?.handlePipelineError(err) }
        }
        do {
            try p.start()
        } catch {
            NSLog("BurritoCursor: pipeline failed to start: %@", error.localizedDescription)
            showAlert(title: "Camera failed to start", message: error.localizedDescription)
            return nil
        }
        self.pipeline = p
        revocationPoller.start { [weak self] in
            DispatchQueue.main.async { self?.handleRevocation() }
        }
        // If the HUD is open, give it the new data feed immediately.
        if hud?.isShown == true { attachHUD(to: p) }
        return p
    }

    /// Stop the pipeline if no consumer remains. Idempotent.
    private func maybeStopPipeline() {
        guard let p = pipeline, !p.hasAnyConsumer else { return }
        p.stop()
        pipeline = nil
        revocationPoller.stop()
        hud?.showDisabledState()
    }

    private func handlePipelineError(_ err: Error?) {
        disableCursor()
        detachPreview()
        onboarding?.showPaused()
        detachHUD()
        pipeline?.stop()
        pipeline = nil
        revocationPoller.stop()
        refreshStatusItem()
        showAlert(
            title: "Camera interrupted",
            message: err?.localizedDescription ?? "The camera session was interrupted."
        )
    }

    // MARK: - Cursor consumer

    private func enableCursor() {
        guard checkPermissions() else { return }
        guard let p = ensurePipelineStarted() else { return }

        let coord = InputCoordinator()
        coord.cursorController = CursorController(config: config)
        coord.scrollController = ScrollController(config: config)
        self.cursorCoord = coord

        cursorSub = p.subscribeSnapshot { [weak coord] snap in
            DispatchQueue.main.async { coord?.apply(state: snap.state) }
        }
        isCursorOn = true
    }

    private func disableCursor() {
        if let sub = cursorSub, let p = pipeline { p.unsubscribe(sub) }
        cursorSub = nil
        cursorCoord?.forceRelease()
        cursorCoord = nil
        isCursorOn = false
        maybeStopPipeline()
    }

    // MARK: - Preview consumer

    @objc private func showOnboarding() {
        if onboarding == nil { onboarding = OnboardingWindow() }

        // Order matters for .accessory apps: activate first or the window comes
        // up behind whatever owns focus.
        NSApp.activate(ignoringOtherApps: true)
        onboarding?.showWindow(nil)
        onboarding?.window?.makeKeyAndOrderFront(nil)

        if let win = onboarding?.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: win)
            NotificationCenter.default.addObserver(
                self, selector: #selector(onOnboardingClosed),
                name: NSWindow.willCloseNotification, object: win
            )
        }

        guard let p = ensurePipelineStarted() else {
            onboarding?.showPaused()
            return
        }
        attachPreview(to: p)
    }

    private func attachPreview(to p: PipelineRunner) {
        detachPreview()
        previewFrameSub = p.subscribeFrame { [weak self] buf in
            self?.previewSawFrame = true
            self?.onboarding?.handleFrame(buf)
        }
        previewSnapshotSub = p.subscribeSnapshot { [weak self] snap in
            self?.onboarding?.handleSnapshot(snap)
        }
    }

    private func detachPreview() {
        if let sub = previewFrameSub, let p = pipeline { p.unsubscribe(sub) }
        if let sub = previewSnapshotSub, let p = pipeline { p.unsubscribe(sub) }
        previewFrameSub = nil
        previewSnapshotSub = nil
    }

    @objc private func onOnboardingClosed(_ note: Notification) {
        defer {
            if let win = onboarding?.window {
                NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: win)
            }
        }
        if previewSawFrame {
            UserDefaults.standard.set(true, forKey: "onboardingShown")
        }
        detachPreview()
        maybeStopPipeline()
    }

    // MARK: - HUD consumer

    @objc private func showDebugHUD() {
        if hud == nil { hud = DebugHUD() }
        NSApp.activate(ignoringOtherApps: true)
        hud?.showWindow(nil)
        hud?.window?.makeKeyAndOrderFront(nil)
        if let p = pipeline {
            attachHUD(to: p)
        } else {
            hud?.showDisabledState()
        }
    }

    private func attachHUD(to p: PipelineRunner) {
        detachHUD()
        let cfg = config
        hudSub = p.subscribeSnapshot { [weak self] snap in
            self?.hud?.update(snapshot: snap, config: cfg)
        }
    }

    private func detachHUD() {
        if let sub = hudSub, let p = pipeline { p.unsubscribe(sub) }
        hudSub = nil
    }

    // MARK: - Permissions

    private func checkPermissions() -> Bool {
        switch PermissionsManager.check() {
        case .granted:
            return true
        case .cameraNotDetermined:
            // System prompt is shown; user comes back and clicks again.
            return false
        case .cameraDenied:
            showAlert(
                title: "Camera access denied",
                message: "Grant Camera permission in System Settings → Privacy & Security → Camera, then re-enable."
            )
            return false
        case .accessibilityMissing:
            showAlert(
                title: "Accessibility access required",
                message: "Grant Accessibility permission in System Settings → Privacy & Security → Accessibility, then re-enable."
            )
            return false
        }
    }

    /// Common revocation path: triggered by the poller, activation observer,
    /// and wake observer.
    private func handleRevocation() {
        guard pipeline != nil, !PermissionsManager.stillGranted() else { return }
        disableCursor()
        detachPreview()
        onboarding?.showPaused()
        refreshStatusItem()
        showAlert(
            title: "Permission revoked",
            message: "Burrito Cursor has been disabled because Camera or Accessibility access is no longer granted."
        )
    }

    // MARK: - Lifecycle observers

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
        cursorCoord?.forceRelease()
        if isCursorOn { disableCursor(); refreshStatusItem() }
    }

    @objc private func onWake() { handleRevocation() }
    @objc private func onActivation() { handleRevocation() }

    // MARK: - Hotkey + signals

    private func installHotkey() {
        KeyboardShortcuts.onKeyDown(for: .toggleBurritoCursor) { [weak self] in
            self?.toggle()
        }
    }

    /// Catch SIGINT/SIGTERM so a `kill` mid-click doesn't leave a stuck mouseDown.
    /// `applicationWillTerminate` is NSApplication-only and doesn't fire on signals.
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.cursorCoord?.forceRelease()
                NSApp.terminate(nil)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    // MARK: - UI helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
