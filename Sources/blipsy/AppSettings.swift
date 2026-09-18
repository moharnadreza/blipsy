import Foundation
import Combine
import ServiceManagement

/// User preferences, persisted to `UserDefaults`. `onChange` lets the monitor
/// restart its loop the moment a setting that affects probing changes.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Fired when a probing-relevant setting changes (target / interval / probes) - restarts probing.
    var onChange: (() -> Void)?
    /// Fired when a display-only setting changes (e.g. show latency) - re-renders now, no re-probe.
    var onDisplayChange: (() -> Void)?

    /// Suppresses per-property `onChange` so a batch apply restarts probing once.
    private var suppressOnChange = false

    @Published var targetsText: String { didSet { defaults.set(targetsText, forKey: Keys.targets); notifyChange() } }
    @Published var interval: Int       { didSet { defaults.set(interval, forKey: Keys.interval); notifyChange() } }
    @Published var probeCount: Int     { didSet { defaults.set(probeCount, forKey: Keys.probeCount); notifyChange() } }
    @Published var showLatency: Bool   { didSet { defaults.set(showLatency, forKey: Keys.showLatency); onDisplayChange?() } }
    @Published var notifyOnChange: Bool { didSet { defaults.set(notifyOnChange, forKey: Keys.notify) } }
    @Published var notificationSound: String { didSet { defaults.set(notificationSound, forKey: Keys.sound) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin); applyLoginItem() } }

    /// The available notification sounds. "Default" uses the system alert;
    /// "None" is silent; the rest are macOS system sounds played on the event.
    static let soundChoices = ["Default", "None", "Ping", "Glass", "Submarine", "Funk", "Hero", "Bottle", "Pop", "Tink", "Sosumi"]

    private func notifyChange() {
        if !suppressOnChange { onChange?() }
    }

    /// Apply the monitoring fields together (from the Settings "Save" button) so
    /// probing restarts exactly once, not on every keystroke.
    func applyMonitoring(targetsText: String, interval: Int, probeCount: Int) {
        suppressOnChange = true
        self.targetsText = targetsText
        self.interval = min(max(1, interval), 3600)   // 1s … 1h
        self.probeCount = min(max(1, probeCount), 20)
        suppressOnChange = false
        onChange?()
    }

    init() {
        defaults.register(defaults: [
            Keys.targets: "8.8.8.8",
            Keys.interval: 2,
            Keys.probeCount: 5,
            Keys.showLatency: true,
            Keys.notify: true,
            Keys.sound: "Default",
            Keys.launchAtLogin: false,
        ])
        targetsText      = defaults.string(forKey: Keys.targets) ?? "8.8.8.8"
        interval         = defaults.integer(forKey: Keys.interval)
        probeCount       = defaults.integer(forKey: Keys.probeCount)
        showLatency      = defaults.bool(forKey: Keys.showLatency)
        notifyOnChange   = defaults.bool(forKey: Keys.notify)
        notificationSound = defaults.string(forKey: Keys.sound) ?? "Default"
        launchAtLogin    = defaults.bool(forKey: Keys.launchAtLogin)
    }

    private func applyLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else             { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("blipsy: could not update login item - \(error.localizedDescription)")
        }
    }

    private enum Keys {
        static let targets = "targets"
        static let interval = "interval"
        static let probeCount = "probeCount"
        static let showLatency = "showLatency"
        static let notify = "notify"
        static let sound = "sound"
        static let launchAtLogin = "launchAtLogin"
    }
}
