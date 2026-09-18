import Foundation
import Combine

/// Owns the settings and the periodic probing loop, and publishes the latest
/// per-target statuses plus the aggregated (worst-of) state for the menu bar icon.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statuses: [TargetStatus] = []
    @Published private(set) var aggregate: ConnectionState = .unknown
    @Published private(set) var isPaused = false
    @Published private(set) var lastChecked: Date?
    /// Rolling connectivity history for the past hour (one sample per cycle).
    @Published private(set) var history: [Sample] = []

    static let historyWindow: TimeInterval = 3600

    let settings = AppSettings()

    /// Called after every cycle so the status-item controller can re-render.
    var onUpdate: ((ConnectionState, [TargetStatus]) -> Void)?

    /// > 40% packet loss ⇒ yellow, per the spec.
    private let lossThreshold = 0.40

    private var loopTask: Task<Void, Never>?

    func start() {
        settings.onChange = { [weak self] in self?.restart() }
        settings.onDisplayChange = { [weak self] in self?.refreshDisplay() }
        restart()
    }

    /// Re-render the menu bar from cached results, without re-probing.
    func refreshDisplay() {
        onUpdate?(aggregate, statuses)
    }

    /// Seed the model with fixed data for offscreen rendering (screenshots/previews).
    func loadPreview(statuses: [TargetStatus], history: [Sample], lastChecked: Date) {
        self.statuses = statuses
        self.aggregate = statuses.map(\.state).max(by: { $0.severity < $1.severity }) ?? .unknown
        self.history = history
        self.lastChecked = lastChecked
    }

    /// Re-run immediately (also used by "Check now").
    func restart() {
        guard !isPaused else { return }
        loopTask?.cancel()

        // Reflect the new target list right away so Save feels instant: keep known
        // targets' last state, show newly-added ones as "checking…". Real results
        // land as each probe completes.
        let targets = Target.parseList(settings.targetsText)
        let previous = statuses
        statuses = targets.map { target in
            previous.first { $0.id == target.id }
                ?? TargetStatus(target: target, state: .unknown, latencyMS: nil, loss: 0)
        }
        publish(markChecked: false)

        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            loopTask?.cancel()
            loopTask = nil
        } else {
            restart()
        }
    }

    // MARK: - Loop

    private func runLoop() async {
        while !Task.isCancelled {
            await runCycle()
            let seconds = max(1, settings.interval)
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        }
    }

    private func runCycle() async {
        let targets = Target.parseList(settings.targetsText)
        let probeCount = max(1, settings.probeCount)
        let timeout = min(Double(max(1, settings.interval)), 3.0)
        let threshold = lossThreshold

        guard !targets.isEmpty else {
            statuses = []
            publish()
            return
        }

        var collected: [TargetStatus] = []
        await withTaskGroup(of: TargetStatus.self) { group in
            for target in targets {
                group.addTask {
                    await AppModel.checkTarget(target, probeCount: probeCount,
                                               timeout: timeout, lossThreshold: threshold)
                }
            }
            for await status in group { collected.append(status) }
        }

        // A restart cancelled us mid-cycle - don't publish this stale target list.
        guard !Task.isCancelled else { return }

        // Restore the order the user typed them in.
        statuses = targets.compactMap { t in collected.first { $0.id == t.id } }
        publish()
    }

    /// Runs off the main actor: probes one target `probeCount` times and summarizes.
    nonisolated static func checkTarget(_ target: Target, probeCount: Int,
                                        timeout: Double, lossThreshold: Double) async -> TargetStatus {
        switch target.kind {
        case .http:
            guard let url = URL(string: target.raw) else {
                return TargetStatus(target: target, state: .down, latencyMS: nil, loss: 1)
            }
            return await measure(HTTPProbe(url: url), target: target,
                                 probeCount: probeCount, timeout: timeout, lossThreshold: lossThreshold)

        case .icmp:
            let icmp = await measure(ICMPProbe(host: target.raw), target: target,
                                    probeCount: probeCount, timeout: timeout, lossThreshold: lossThreshold)
            guard icmp.state == .down else { return icmp }

            // ICMP failed completely - it may be blocked by a VPN (e.g. Tailscale)
            // or a firewall. Confirm with a VPN-aware TLS check before calling it down.
            let tls = await TLSProbe(host: target.raw, port: 443).probeOnce(timeout: timeout)
            if tls.success {
                return TargetStatus(target: target, state: .connected,
                                    latencyMS: tls.rtt.map { $0 * 1000 }, loss: 0)
            }
            return icmp
        }
    }

    nonisolated static func measure(_ probe: ReachabilityProbe, target: Target,
                                    probeCount: Int, timeout: Double,
                                    lossThreshold: Double) async -> TargetStatus {
        var successes = 0
        var rtts: [Double] = []
        for _ in 0..<probeCount {
            let result = await probe.probeOnce(timeout: timeout)
            if result.success {
                successes += 1
                if let rtt = result.rtt { rtts.append(rtt) }
            }
        }
        let summary = ProbeSummary(successes: successes, total: probeCount,
                                   averageRTT: rtts.isEmpty ? nil : rtts.reduce(0, +) / Double(rtts.count))
        return TargetStatus(target: target,
                            state: summary.state(lossThreshold: lossThreshold),
                            latencyMS: summary.averageRTT.map { $0 * 1000 },
                            loss: summary.loss)
    }

    private func publish(markChecked: Bool = true) {
        aggregate = statuses.map(\.state).max(by: { $0.severity < $1.severity }) ?? .unknown
        if markChecked {
            let now = Date()
            lastChecked = now
            // Record a real cycle (not the instant "checking…" reflection).
            history.append(Sample(date: now, state: aggregate,
                                  latencyMS: statuses.compactMap(\.latencyMS).max()))
            let cutoff = now.addingTimeInterval(-Self.historyWindow)
            history.removeAll { $0.date < cutoff }
        }
        onUpdate?(aggregate, statuses)
    }
}
