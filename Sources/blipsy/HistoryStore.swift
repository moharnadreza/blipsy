import Foundation
import Combine

/// One recorded connection-state transition.
struct StatusEvent: Codable, Sendable {
    let date: Date
    let state: ConnectionState
}

/// A period the connection was degraded (lossy) or down, derived from transitions.
struct Outage: Identifiable, Sendable {
    let start: Date
    let end: Date?            // nil while still ongoing
    let state: ConnectionState   // .down or .lossy

    var id: Date { start }
    func duration(now: Date) -> TimeInterval { (end ?? now).timeIntervalSince(start) }
    var isOngoing: Bool { end == nil }

    /// Derive outage intervals from a chronological list of state transitions.
    /// Each down/lossy event runs until the next event (or "now" if it's the last).
    static func derive(from events: [StatusEvent], now: Date) -> [Outage] {
        var result: [Outage] = []
        for (i, event) in events.enumerated() where event.state == .down || event.state == .lossy {
            let end = (i + 1 < events.count) ? events[i + 1].date : nil
            result.append(Outage(start: event.date, end: end, state: event.state))
        }
        return result.reversed()   // newest first
    }
}

/// Persists connection-state transitions to disk so outages survive relaunch,
/// and derives a day-by-day outage history from them.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var events: [StatusEvent] = []

    private let fileURL: URL
    private let retention: TimeInterval = 30 * 24 * 3600   // keep ~30 days

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("blipsy", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    /// In-memory store seeded with fixed events, for previews/tests (no disk I/O).
    init(previewEvents: [StatusEvent]) {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("blipsy-preview.json")
        events = previewEvents
    }

    /// Record a transition. Only genuine state changes are stored (not every cycle),
    /// and "checking" is ignored.
    func record(_ state: ConnectionState, at date: Date) {
        guard state != .unknown else { return }
        if let last = events.last, last.state == state { return }
        events.append(StatusEvent(date: date, state: state))
        prune()
        save()
    }

    /// Outages (down or lossy intervals), newest first.
    func outages(now: Date) -> [Outage] {
        Outage.derive(from: events, now: now)
    }

    // MARK: - Persistence

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        // Keep one event before the cutoff so the oldest interval stays complete.
        guard let firstRecent = events.firstIndex(where: { $0.date >= cutoff }), firstRecent > 1 else { return }
        events.removeFirst(firstRecent - 1)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StatusEvent].self, from: data) else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
