import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let scroll = ScrollDirectionController()
    private var monitor: MouseMonitor!

    /// When paused, mouse attach/detach no longer drives the setting.
    private var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        monitor = MouseMonitor { [weak self] connected in
            self?.mouseStateChanged(connected: connected)
        }
        monitor.start()

        // Apply the correct state for whatever is connected right now.
        applyForCurrentMouseState()
        refreshUI()

        // Keep the menu in sync if the user changes scrolling elsewhere.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(externalChange),
            name: NSNotification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil
        )
    }

    // MARK: - Core logic

    /// Mouse connected  → natural scrolling OFF (traditional mouse wheel).
    /// No mouse (trackpad) → natural scrolling ON.
    private func applyForCurrentMouseState() {
        scroll.setNaturalScrolling(enabled: !monitor.isMouseConnected)
    }

    private func mouseStateChanged(connected: Bool) {
        if !paused {
            scroll.setNaturalScrolling(enabled: !connected)
        }
        refreshUI()
    }

    @objc private func externalChange() {
        DispatchQueue.main.async { [weak self] in self?.refreshUI() }
    }

    // MARK: - UI

    private func refreshUI() {
        let mouse = monitor.isMouseConnected
        if let button = statusItem.button {
            let symbol = mouse ? "computermouse.fill" : "laptopcomputer"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Natural Scrolling Auto")
            button.image?.isTemplate = true
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let mouse = monitor.isMouseConnected
        let natural = scroll.isNaturalEnabled

        menu.addItem(disabled("Mouse: \(mouse ? "connected" : "not connected")"))
        menu.addItem(disabled("Natural scrolling: \(natural ? "On" : "Off")"))
        if !scroll.liveApplyAvailable {
            menu.addItem(disabled("⚠︎ Live toggle unavailable (applies on next login)"))
        }
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(title: "Pause automatic switching",
                                   action: #selector(togglePause),
                                   keyEquivalent: "")
        pauseItem.target = self
        pauseItem.state = paused ? .on : .off
        menu.addItem(pauseItem)

        let manualItem = NSMenuItem(title: natural ? "Switch to mouse (off)" : "Switch to natural (on)",
                                    action: #selector(manualToggle),
                                    keyEquivalent: "")
        manualItem.target = self
        menu.addItem(manualItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Open at Login",
                                   action: #selector(toggleLoginItem),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func togglePause() {
        paused.toggle()
        if !paused { applyForCurrentMouseState() } // re-sync on resume
        refreshUI()
    }

    /// Manual override: flip the setting now. Pauses automatic switching so the
    /// app doesn't immediately undo the user's choice.
    @objc private func manualToggle() {
        scroll.setNaturalScrolling(enabled: !scroll.isNaturalEnabled)
        paused = true
        refreshUI()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[NaturalScrollingAuto] login item toggle failed: \(error)")
        }
        refreshUI()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
