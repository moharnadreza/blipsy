import Foundation

/// How a target is reached.
enum TargetKind: Sendable {
    case icmp   // bare IP or hostname → ICMP echo (ping)
    case http   // http(s):// URL → HTTP HEAD request
}

/// A single thing blipsy watches. Parsed from the comma-separated target field.
struct Target: Identifiable, Hashable, Sendable {
    let raw: String       // original text, e.g. "8.8.8.8" or "https://github.com"
    let kind: TargetKind
    let display: String   // short label shown in the menu

    init?(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.raw = trimmed
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            self.kind = .http
            self.display = URL(string: trimmed)?.host ?? trimmed
        } else {
            self.kind = .icmp
            self.display = trimmed
        }
    }

    var id: String { raw }

    /// Split the settings field (commas or newlines) into concrete targets,
    /// dropping blanks and duplicates while preserving the typed order.
    static func parseList(_ text: String) -> [Target] {
        let separators = CharacterSet(charactersIn: ",\n")
        var seen = Set<String>()
        var result: [Target] = []
        for piece in text.components(separatedBy: separators) {
            guard let target = Target(raw: piece) else { continue }
            if seen.insert(target.id).inserted { result.append(target) }
        }
        return result
    }
}

/// The three states from the spec, plus an initial "unknown".
enum ConnectionState: Sendable {
    case connected   // green  - loss ≤ threshold
    case lossy       // yellow - loss > threshold, still reachable
    case down        // red    - 100% loss
    case unknown     // gray   - no data yet

    /// Higher = worse. Used to aggregate several targets into one icon. `unknown`
    /// ranks lowest so a target still "checking…" doesn't gray out an otherwise
    /// healthy set - a real bad state (lossy/down) always shows through.
    var severity: Int {
        switch self {
        case .unknown:   return 0
        case .connected: return 1
        case .lossy:     return 2
        case .down:      return 3
        }
    }
}

/// The latest result for one target.
struct TargetStatus: Identifiable, Sendable {
    let target: Target
    var state: ConnectionState
    var latencyMS: Double?   // average RTT of successful probes, in ms
    var loss: Double         // 0.0 ... 1.0
    var id: String { target.id }
}

/// A point in the rolling connectivity history (one per probe cycle).
struct Sample: Sendable {
    let date: Date
    let state: ConnectionState
    let latencyMS: Double?
}

/// One check cycle's raw outcome for a single target.
struct ProbeSummary: Sendable {
    let successes: Int
    let total: Int
    let averageRTT: Double?  // seconds

    var loss: Double { total == 0 ? 1 : Double(total - successes) / Double(total) }

    func state(lossThreshold: Double) -> ConnectionState {
        if successes == 0 { return .down }
        if loss > lossThreshold { return .lossy }
        return .connected
    }
}

/// Formats a latency in ms, keeping one decimal below 100 ms so two similar
/// targets are distinguishable (e.g. `14.8 ms` vs `15.3 ms`).
func formatLatency(_ ms: Double) -> String {
    ms < 100 ? String(format: "%.1f ms", ms) : "\(Int(ms.rounded())) ms"
}

/// Loss as a whole percent. Rounds (not truncates) so 0.6 reads as 60%, not 59%.
func lossPercent(_ loss: Double) -> Int {
    Int((loss * 100).rounded())
}

/// Human-readable one-liner for a target row / notification body.
func detailText(_ s: TargetStatus) -> String {
    switch s.state {
    case .down:
        return "unreachable"
    case .lossy:
        let ms = s.latencyMS.map(formatLatency) ?? "-"
        return "\(ms) · \(lossPercent(s.loss))% loss"
    case .connected:
        return s.latencyMS.map(formatLatency) ?? "connected"
    case .unknown:
        return "checking…"
    }
}
