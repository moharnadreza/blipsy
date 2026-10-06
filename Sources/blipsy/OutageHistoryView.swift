import SwiftUI

/// A day-by-day log of outages (down) and degraded (packet-loss) periods, so you
/// can see exactly when the connection dropped.
struct OutageHistoryView: View {
    @ObservedObject var history: HistoryStore
    /// ImageRenderer (screenshots) can't draw a ScrollView; pass false there.
    var scrolls: Bool = true

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let dayName: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    var body: some View {
        let now = Date()
        let groups = grouped(history.outages(now: now), now: now)

        VStack(alignment: .leading, spacing: 0) {
            BrandHeader(title: "Outage history")
            if let s = summary(now: now) {
                HStack(alignment: .top, spacing: 0) {
                    metric("Uptime", uptimeText(s.uptime))
                    metric("Downtime", compactDuration(s.down))
                    metric("Window", "7 days")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            Divider()

            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 30)).foregroundStyle(Color(nsColor: .systemGreen))
                    Text("No outages recorded").font(.system(size: 13, weight: .medium))
                    Text("Your connection has been stable.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scrolls {
                ScrollView { list(groups, now: now) }
            } else {
                list(groups, now: now)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 380, height: 460)
    }

    private func list(_ groups: [DayGroup], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groups, id: \.day) { group in
                section(group, now: now)
            }
        }
        .padding(16)
    }

    private func section(_ group: DayGroup, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayLabel(group.day, now: now))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(group.outages.count) · \(compactDuration(group.downtime)) down")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(group.outages) { outage in
                HStack(spacing: 10) {
                    Circle().fill(stateColor(outage.state)).frame(width: 8, height: 8)
                    Text(timeRange(outage))
                        .font(.system(size: 12)).monospacedDigit()
                    Spacer()
                    Text(outage.state == .down ? "down" : "packet loss")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(compactDuration(outage.duration(now: now)))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Summary (last 7 days)

    // Mirrors the metric grid in the menu panel (LATENCY / LOSS / CHECKED).
    private func metric(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key.uppercased()).font(.system(size: 9, weight: .semibold))
                .tracking(0.5).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func uptimeText(_ fraction: Double) -> String {
        fraction >= 0.9995 ? "100%" : String(format: "%.1f%%", fraction * 100)
    }

    /// Uptime and total downtime over the last 7 days of monitored time (only
    /// counts actual down periods; packet loss still counts as "up but degraded").
    private func summary(now: Date) -> (uptime: Double, down: TimeInterval)? {
        guard let first = history.events.first?.date else { return nil }
        let windowStart = max(first, now.addingTimeInterval(-7 * 24 * 3600))
        let monitored = now.timeIntervalSince(windowStart)
        guard monitored > 0 else { return nil }
        var down: TimeInterval = 0
        for outage in history.outages(now: now) where outage.state == .down {
            let s = max(outage.start, windowStart)
            let e = outage.end ?? now
            if e > s { down += e.timeIntervalSince(s) }
        }
        return (max(0, min(1, 1 - down / monitored)), down)
    }

    // MARK: - Grouping & formatting

    private struct DayGroup { let day: Date; let outages: [Outage]; let downtime: TimeInterval }

    private func grouped(_ outages: [Outage], now: Date) -> [DayGroup] {
        let cal = Calendar.current
        var map: [Date: [Outage]] = [:]
        for outage in outages {
            let day = cal.startOfDay(for: outage.start)
            map[day, default: []].append(outage)
        }
        return map.keys.sorted(by: >).map { day in
            let items = map[day]!
            let downtime = items.filter { $0.state == .down }.reduce(0) { $0 + $1.duration(now: now) }
            return DayGroup(day: day, outages: items, downtime: downtime)
        }
    }

    private func dayLabel(_ day: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return Self.dayName.string(from: day)
    }

    private func timeRange(_ outage: Outage) -> String {
        let start = Self.time.string(from: outage.start)
        guard let end = outage.end else { return "\(start) → now" }
        return "\(start) → \(Self.time.string(from: end))"
    }

    private func compactDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        let h = s / 3600, m = (s % 3600) / 60
        return "\(h)h \(m)m"
    }
}
