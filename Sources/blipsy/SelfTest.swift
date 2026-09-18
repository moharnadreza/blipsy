import Foundation

/// Command-line probe check - no GUI. Runs targets concurrently exactly like the
/// app does. Usage: `blipsy --selftest 8.8.8.8,1.1.1.1`
enum SelfTest {
    static func run(arguments: [String]) {
        let arg = arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "8.8.8.8"
        let targets = Target.parseList(arg)
        guard !targets.isEmpty else { print("no valid targets"); return }
        print("blipsy selftest → \(targets.map(\.raw).joined(separator: ", ")) (5 probes each, concurrent)")

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            var results: [(Int, TargetStatus)] = []
            await withTaskGroup(of: (Int, TargetStatus).self) { group in
                for (index, target) in targets.enumerated() {
                    group.addTask {
                        (index, await AppModel.checkTarget(target, probeCount: 5,
                                                           timeout: 2, lossThreshold: 0.40))
                    }
                }
                for await result in group { results.append(result) }
            }
            for (_, s) in results.sorted(by: { $0.0 < $1.0 }) {
                let ms = s.latencyMS.map { String(format: "%.1f ms", $0) } ?? "-"
                print(String(format: "  %@ → %@  ·  loss %.0f%%  ·  avg %@",
                             s.target.display, label(s.state), s.loss * 100, ms))
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func label(_ state: ConnectionState) -> String {
        switch state {
        case .connected: return "connected (green)"
        case .lossy:     return "packet loss (yellow)"
        case .down:      return "down (red)"
        case .unknown:   return "unknown"
        }
    }
}
