import SwiftUI

/// A compact "past hour" status timeline - like a mini status page. The bar is
/// split into 1-minute buckets colored by the worst state seen in each; empty
/// buckets read as faint "no data". Cheap: a few hundred samples, drawn on demand.
struct HistoryView: View {
    let samples: [Sample]
    let now: Date

    private let buckets = 60
    private let window = AppModel.historyWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PAST HOUR")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(uptimeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Canvas { context, size in
                // Assign each sample to a bucket by index (clamped), so the newest
                // sample - whose time == `now` - lands in the last bucket instead
                // of being dropped by a half-open range check. Keep the worst state.
                var bucketState = [ConnectionState?](repeating: nil, count: buckets)
                let start = now.addingTimeInterval(-window)
                for sample in samples {
                    let fraction = sample.date.timeIntervalSince(start) / window
                    let idx = max(0, min(buckets - 1, Int(fraction * Double(buckets))))
                    if let existing = bucketState[idx] {
                        if sample.state.severity > existing.severity { bucketState[idx] = sample.state }
                    } else {
                        bucketState[idx] = sample.state
                    }
                }

                let bucketWidth = size.width / CGFloat(buckets)
                for i in 0..<buckets {
                    let color = bucketState[i].map(stateColor) ?? Color.secondary.opacity(0.15)
                    let rect = CGRect(x: CGFloat(i) * bucketWidth + 0.5, y: 0,
                                      width: bucketWidth - 1, height: size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                }
            }
            .frame(height: 22)

            HStack {
                Text("60 min ago").font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer()
                Text("now").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private var uptimeText: String {
        let windowed = samples.filter { $0.date >= now.addingTimeInterval(-window) }
        guard !windowed.isEmpty else { return "-" }
        let reachable = windowed.filter { $0.state == .connected || $0.state == .lossy }.count
        let pct = Int((Double(reachable) / Double(windowed.count) * 100).rounded())
        return "\(pct)% up"
    }
}
