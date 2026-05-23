import AppKit

/// Builds the status-bar `NSMenu` from a snapshot of UI state. Pure
/// construction — no `AppController` state lookups, no side effects.
enum MenuBuilder {
    struct State {
        let isCursorOn: Bool
    }

    struct Actions {
        let toggle: Selector
        let showPreview: Selector
        let showHUD: Selector
    }

    static func build(state: State, target: AnyObject, actions: Actions) -> NSMenu {
        let menu = NSMenu()

        let dot = state.isCursorOn ? "🟢" : "⚪️"
        let header = NSMenuItem(
            title: "\(dot)  \(state.isCursorOn ? "Cursor enabled" : "Cursor disabled")",
            action: nil, keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(
            title: state.isCursorOn ? "Disable Cursor" : "Enable Cursor",
            action: actions.toggle, keyEquivalent: "h"
        )
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        toggleItem.target = target
        toggleItem.image = symbol(state.isCursorOn ? "pause.circle" : "play.circle")
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        let previewItem = NSMenuItem(title: "Camera Preview…", action: actions.showPreview, keyEquivalent: "")
        previewItem.target = target
        previewItem.image = symbol("camera.viewfinder")
        menu.addItem(previewItem)

        let hudItem = NSMenuItem(title: "Show Debug HUD", action: actions.showHUD, keyEquivalent: "")
        hudItem.target = target
        hudItem.image = symbol("chart.bar.doc.horizontal")
        menu.addItem(hudItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Burrito Cursor",
            action: #selector(NSApp.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = symbol("power")
        menu.addItem(quitItem)

        return menu
    }

    /// SF Symbol sized for menu rows.
    private static func symbol(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }
}
