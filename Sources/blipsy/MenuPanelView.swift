import SwiftUI

/// The dropdown panel shown from the menu bar - mirrors the demo: a status
/// header, a metrics grid (single target) or per-target rows (multiple), and
/// the action rows.
struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    var onSettings: () -> Void
    var onAbout: () -> Void
    var onQuit: () -> Void

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.isPaused {
                Text("Monitoring paused")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else if model.statuses.isEmpty {
                Text("No targets - open Settings")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else if model.statuses.count == 1, let only = model.statuses.first {
                singleMetrics(only)
            } else {
                Divider().padding(.vertical, 8)
                targetRows
            }

            if !model.isPaused, !model.history.isEmpty {
                Divider().padding(.vertical, 8)
                HistoryView(samples: model.history, now: model.lastChecked ?? Date())
            }

            Divider().padding(.vertical, 8)
            actions
        }
        .padding(12)
        .frame(width: 264)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(model.aggregate))
                .frame(width: 9, height: 9)
                .shadow(color: color(model.aggregate).opacity(0.4), radius: 2)
            Text(title(model.aggregate))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
    }

    // MARK: - Single target: metrics grid

    private func singleMetrics(_ s: TargetStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                metric("Latency", s.latencyMS.map(formatLatency) ?? "-")
                metric("Loss", "\(lossPercent(s.loss))%")
                metric("Checked", model.lastChecked.map { Self.clock.string(from: $0) } ?? "-")
            }
            Text(configLine(s.target))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func metric(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Multiple targets: rows

    private var targetRows: some View {
        VStack(spacing: 7) {
            ForEach(model.statuses) { s in
                HStack(spacing: 8) {
                    Circle().fill(color(s.state)).frame(width: 8, height: 8)
                    Text(s.target.display).font(.system(size: 12))
                    Spacer()
                    Text(detailText(s))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 2) {
            MenuRowButton(title: "Check Now", shortcut: "⌘R") { model.restart() }
            MenuRowButton(title: model.isPaused ? "Resume Monitoring" : "Pause Monitoring") { model.togglePause() }
            MenuRowButton(title: "Settings…", shortcut: "⌘,") { onSettings() }
            MenuRowButton(title: "About blipsy") { onAbout() }
            Divider().padding(.vertical, 4)
            MenuRowButton(title: "Quit blipsy", shortcut: "⌘Q") { onQuit() }
        }
    }

    // MARK: - Helpers

    private func color(_ state: ConnectionState) -> Color { stateColor(state) }

    private func title(_ state: ConnectionState) -> String {
        switch state {
        case .connected: return "Connected"
        case .lossy:     return "Packet loss"
        case .down:      return "Down"
        case .unknown:   return "Checking…"
        }
    }

    private func configLine(_ target: Target) -> String {
        let kind = target.kind == .icmp ? "ICMP" : "HTTP"
        return "\(target.display) · every \(model.settings.interval)s · \(kind)"
    }
}

/// A menu-style row button that highlights on hover, like a native menu item.
private struct MenuRowButton: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(hovering ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
