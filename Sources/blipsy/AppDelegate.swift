import AppKit
import SwiftUI
import UserNotifications

/// Owns the menu bar item: draws the colored status-dot icon, shows the SwiftUI
/// panel in a borderless panel anchored under the icon, opens Settings, and
/// notifies when the state changes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hostingView: NSHostingView<AnyView>!
    private var clickMonitor: Any?
    private var settingsWindow: NSWindowController?
    private var aboutWindow: NSWindowController?
    private var previousState: ConnectionState = .unknown

    /// Gap between the menu bar and the top of the panel.
    private let panelGap: CGFloat = 4
    /// When the panel was last closed - debounces the icon click so the outside-click
    /// monitor and the button action don't close-then-reopen it.
    private var lastCloseAt: TimeInterval = 0
    /// Keeps App Nap from throttling the probe loop while still allowing the Mac to sleep.
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusImage(.unknown)
            button.imagePosition = .imageLeading
            button.action = #selector(togglePanel)
            button.target = self
        }

        buildPanel()
        installEditMenu()
        requestNotificationAuthorization()

        model.onUpdate = { [weak self] state, statuses in
            self?.render(state: state, statuses: statuses)
        }

        // Keep the 2s cadence steady when unfocused (prevent App Nap), but still
        // let the machine sleep normally when idle.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Monitoring the internet connection")

        // Re-check immediately after the Mac wakes, so status isn't stale.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.restart() }
        }

        render(state: .unknown, statuses: [])
        model.start()
    }

    // MARK: - Panel

    private func buildPanel() {
        // Material + rounding done inside SwiftUI and clipped, so everything
        // outside the rounded shape is transparent (no white window backing).
        let content = MenuPanelView(
            model: model,
            onSettings: { [weak self] in self?.openSettings() },
            onAbout: { [weak self] in self?.openAbout() },
            onQuit: { NSApp.terminate(nil) })
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = hostingView
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// blipsy is a menu-bar agent with no visible menu bar, but text fields (in
    /// Settings) need an Edit menu for Cmd+A/C/V/X/Z to work. This menu stays
    /// hidden for an accessory app; it only supplies those key equivalents.
    private func installEditMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit blipsy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else if ProcessInfo.processInfo.systemUptime - lastCloseAt > 0.25 {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        // Size the panel to the SwiftUI content (force layout so it's non-zero).
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        panel.setContentSize(size)

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        // visibleFrame's top already sits below the menu bar AND the notch, so
        // anchoring the panel there keeps it clear of the notch on any display.
        let visible = buttonWindow.screen?.visibleFrame ?? screenRect
        let topY = visible.maxY - panelGap
        var origin = NSPoint(x: screenRect.maxX - size.width, y: topY - size.height)
        origin.x = max(visible.minX + 4, min(origin.x, visible.maxX - size.width - 4))

        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)

        // Close when the user clicks anywhere outside our app.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastCloseAt = ProcessInfo.processInfo.systemUptime
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Rendering

    private func render(state: ConnectionState, statuses: [TargetStatus]) {
        if let button = statusItem.button {
            button.image = statusImage(state)
            if model.settings.showLatency {
                // Left-aligned, single leading space. Monospaced digits keep each
                // digit the same width, so the icon doesn't jitter as latency
                // fluctuates within the same digit count. When nothing is
                // reachable there's no latency, so show the state instead of blank.
                let label: String
                if let ms = statuses.compactMap(\.latencyMS).max() {
                    label = "\(Int(ms.rounded())) ms"
                } else if state == .down {
                    label = "Down"
                } else {
                    label = "…"
                }
                let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                button.attributedTitle = NSAttributedString(string: " " + label, attributes: [.font: font])
            } else {
                button.attributedTitle = NSAttributedString(string: "")
            }
        }

        if state.severity != previousState.severity {
            if previousState != .unknown, model.settings.notifyOnChange {
                notifyStateChange(state, statuses: statuses)
            }
            previousState = state
        }
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        closePanel()
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(settings: model.settings))
            let window = NSWindow(contentViewController: host)
            window.title = "blipsy Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.window?.center()
        settingsWindow?.showWindow(nil)
    }

    @objc private func openAbout() {
        closePanel()
        if aboutWindow == nil {
            let host = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: host)
            window.title = "About blipsy"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            aboutWindow = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.window?.center()
        aboutWindow?.showWindow(nil)
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyStateChange(_ state: ConnectionState, statuses: [TargetStatus]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        switch state {
        case .down:      content.title = "blipsy: connection down"
        case .lossy:     content.title = "blipsy: packet loss"
        case .connected: content.title = "blipsy: back online"
        case .unknown:   return
        }
        if let worst = statuses.max(by: { $0.state.severity < $1.state.severity }) {
            content.body = "\(worst.target.display): \(detailText(worst))"
        }

        // Sound: "None" is silent, "Default" is the system alert, others are macOS
        // system sounds we play ourselves.
        switch model.settings.notificationSound {
        case "None":    content.sound = nil
        case "Default": content.sound = .default
        default:
            content.sound = nil
            NSSound(named: model.settings.notificationSound)?.play()
        }

        // Just the app's own icon (left side) plus the text. macOS can't swap the
        // notification icon per event, so no attachment, so no second icon.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Icon

    private func nsColor(_ state: ConnectionState) -> NSColor {
        switch state {
        case .connected: return .systemGreen
        case .lossy:     return .systemYellow
        case .down:      return .systemRed
        case .unknown:   return .systemGray
        }
    }

    /// A clean filled status dot - shape stays constant, only the color changes.
    private func statusImage(_ state: ConnectionState) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        nsColor(state).setFill()
        NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 9, height: 9)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
