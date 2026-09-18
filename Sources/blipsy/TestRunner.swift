import Foundation

/// A tiny dependency-free regression suite runnable without Xcode: `blipsy --test`.
/// Covers the pure logic - target parsing, state aggregation, loss thresholds,
/// and display formatting. Exits non-zero if anything fails (CI-friendly).
enum TestRunner {
    private nonisolated(unsafe) static var passed = 0
    private nonisolated(unsafe) static var failed = 0

    static func run() -> Int32 {
        print("blipsy regression tests\n")

        group("Target parsing")
        eq("single IP → ICMP", Target.parseList("8.8.8.8").first?.kind, .icmp)
        eq("IP display", Target.parseList("8.8.8.8").first?.display, "8.8.8.8")
        eq("https URL → HTTP", Target.parseList("https://github.com/x").first?.kind, .http)
        eq("URL display is host", Target.parseList("https://github.com/x").first?.display, "github.com")
        eq("uppercase scheme → HTTP", Target.parseList("HTTPS://EXAMPLE.COM").first?.kind, .http)
        eq("hostname no scheme → ICMP", Target.parseList("example.com").first?.kind, .icmp)
        eq("comma list order", Target.parseList("8.8.8.8, 1.1.1.1, https://github.com").map(\.display),
           ["8.8.8.8", "1.1.1.1", "github.com"])
        eq("comma list kinds", Target.parseList("8.8.8.8, 1.1.1.1, https://github.com").map(\.kind),
           [.icmp, .icmp, .http])
        eq("whitespace trimmed", Target.parseList("  8.8.8.8 ,  1.1.1.1  ").map(\.display), ["8.8.8.8", "1.1.1.1"])
        eq("newlines separate", Target.parseList("8.8.8.8\n1.1.1.1").count, 2)
        ok("empty → none", Target.parseList("").isEmpty)
        ok("blanks → none", Target.parseList(", ,\n,").isEmpty)
        eq("duplicates removed", Target.parseList("8.8.8.8, 8.8.8.8, 1.1.1.1").map(\.display), ["8.8.8.8", "1.1.1.1"])

        group("State aggregation (worst-of)")
        eq("connected+lossy → lossy", worst([.connected, .lossy]), .lossy)
        eq("connected+down → down", worst([.connected, .down]), .down)
        eq("lossy+down → down", worst([.lossy, .down]), .down)
        eq("all connected → connected", worst([.connected, .connected]), .connected)
        eq("checking doesn't gray healthy", worst([.connected, .unknown]), .connected)
        eq("down beats checking", worst([.unknown, .down]), .down)

        group("Packet-loss thresholds (>40% = yellow)")
        eq("5/5 → connected", ProbeSummary(successes: 5, total: 5, averageRTT: 0.02).state(lossThreshold: 0.40), .connected)
        eq("0/5 → down", ProbeSummary(successes: 0, total: 5, averageRTT: nil).state(lossThreshold: 0.40), .down)
        eq("3/5 (40% loss) → connected", ProbeSummary(successes: 3, total: 5, averageRTT: 0.05).state(lossThreshold: 0.40), .connected)
        eq("2/5 (60% loss) → lossy", ProbeSummary(successes: 2, total: 5, averageRTT: 0.05).state(lossThreshold: 0.40), .lossy)
        eq("5/10 (50% loss) → lossy", ProbeSummary(successes: 5, total: 10, averageRTT: 0.05).state(lossThreshold: 0.40), .lossy)
        eq("loss fraction 0/5", ProbeSummary(successes: 5, total: 5, averageRTT: 0).loss, 0.0)
        eq("loss fraction 0/5 total", ProbeSummary(successes: 0, total: 0, averageRTT: nil).loss, 1.0)

        group("Formatting")
        eq("latency <100 keeps decimal", formatLatency(14.83), "14.8 ms")
        eq("latency 42 → 42.0 ms", formatLatency(42.0), "42.0 ms")
        eq("latency 100 → whole", formatLatency(100.0), "100 ms")
        eq("latency 150.6 rounds", formatLatency(150.6), "151 ms")
        eq("loss 0.6 rounds to 60 (not 59)", lossPercent(0.6), 60)
        eq("loss 0.2 → 20", lossPercent(0.2), 20)
        eq("loss 1.0 → 100", lossPercent(1.0), 100)

        group("detailText")
        eq("connected", detailText(status(.connected, 18.0, 0)), "18.0 ms")
        eq("down", detailText(status(.down, nil, 1)), "unreachable")
        eq("lossy", detailText(status(.lossy, 140.0, 0.6)), "140 ms · 60% loss")
        eq("checking", detailText(status(.unknown, nil, 0)), "checking…")

        // Async: the probe → summary pipeline, driven by a deterministic mock.
        group("Measurement pipeline (mock probe)")
        let semaphore = DispatchSemaphore(value: 0)
        Task { await asyncTests(); semaphore.signal() }
        semaphore.wait()

        print("\n\(failed == 0 ? "PASS" : "FAIL"): \(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    private static func asyncTests() async {
        let target = Target(raw: "8.8.8.8")!
        let hit = ProbeResult(success: true, rtt: 0.020)
        let miss = ProbeResult(success: false, rtt: nil)

        let allOK = await AppModel.measure(MockProbe([hit, hit, hit, hit, hit]),
                                           target: target, probeCount: 5, timeout: 1, lossThreshold: 0.40)
        eq("5/5 → connected", allOK.state, .connected)
        eq("5/5 loss 0", allOK.loss, 0.0)
        eq("5/5 latency 20ms", allOK.latencyMS ?? -1, 20.0)

        let lossy = await AppModel.measure(MockProbe([hit, miss, miss, hit, miss]),
                                           target: target, probeCount: 5, timeout: 1, lossThreshold: 0.40)
        eq("2/5 → lossy", lossy.state, .lossy)
        eq("2/5 loss 0.6", lossy.loss, 0.6)

        let down = await AppModel.measure(MockProbe([miss, miss, miss, miss, miss]),
                                          target: target, probeCount: 5, timeout: 1, lossThreshold: 0.40)
        eq("0/5 → down", down.state, .down)
        ok("0/5 no latency", down.latencyMS == nil)
    }

    private static func eq(_ name: String, _ a: Double?, _ b: Double) {
        eq(name, a ?? .nan, b)
    }

    // MARK: - Helpers

    private static func worst(_ states: [ConnectionState]) -> ConnectionState? {
        states.max(by: { $0.severity < $1.severity })
    }

    private static func status(_ state: ConnectionState, _ ms: Double?, _ loss: Double) -> TargetStatus {
        TargetStatus(target: Target(raw: "8.8.8.8")!, state: state, latencyMS: ms, loss: loss)
    }

    private static func group(_ name: String) { print("• \(name)") }

    private static func ok(_ name: String, _ condition: Bool) {
        if condition { passed += 1 } else { failed += 1; print("  ✗ \(name)") }
    }

    private static func eq<T: Equatable>(_ name: String, _ a: T, _ b: T) {
        if a == b { passed += 1 } else { failed += 1; print("  ✗ \(name): got \(a), expected \(b)") }
    }

    private static func eq(_ name: String, _ a: Double, _ b: Double) {
        if abs(a - b) < 0.0001 { passed += 1 } else { failed += 1; print("  ✗ \(name): got \(a), expected \(b)") }
    }
}

/// A deterministic probe that returns a preset sequence of results - lets us test
/// the measurement pipeline (loss %, state, average latency) without a network.
private final class MockProbe: ReachabilityProbe, @unchecked Sendable {
    private let results: [ProbeResult]
    private let lock = NSLock()
    private var index = 0

    init(_ results: [ProbeResult]) { self.results = results }

    func probeOnce(timeout: Double) async -> ProbeResult {
        lock.lock(); defer { lock.unlock() }
        let result = results[min(index, results.count - 1)]
        index += 1
        return result
    }
}
