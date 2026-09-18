import Foundation
import Network

/// Outcome of a single probe.
struct ProbeResult: Sendable {
    let success: Bool
    let rtt: Double?  // seconds, when known
}

/// Ensures a checked continuation is resumed exactly once from multiple callbacks.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// A pluggable reachability probe. Swapping ICMP for TCP/HTTP later (e.g. for a
/// sandboxed App Store build) means adding a conformer here - nothing else changes.
protocol ReachabilityProbe: Sendable {
    /// Send one probe. Never throws; a failure/timeout is reported as `success == false`.
    func probeOnce(timeout: Double) async -> ProbeResult
}

/// Reaches an http(s) URL with a HEAD request. Any HTTP response counts as reachable.
struct HTTPProbe: ReachabilityProbe {
    let url: URL

    func probeOnce(timeout: Double) async -> ProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        let start = DispatchTime.now()
        do {
            let (_, _) = try await session.data(for: request)
            let rtt = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            return ProbeResult(success: true, rtt: rtt)
        } catch {
            return ProbeResult(success: false, rtt: nil)
        }
    }
}

/// Reaches an IP/hostname with a real ICMP echo (ping).
struct ICMPProbe: ReachabilityProbe {
    let host: String

    func probeOnce(timeout: Double) async -> ProbeResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: ICMPPinger.ping(host: host, timeout: timeout))
            }
        }
    }
}

/// A TLS-handshake reachability check via Network.framework, used as a fallback
/// when ICMP fails. It routes correctly through VPNs (Tailscale/utun) AND, unlike
/// a bare TCP connect, completing the TLS handshake forces a real round-trip to
/// the destination, so full-tunnel proxies (v2ray/Streisand) can't report a
/// bogus ~2ms local latency. Certificate trust is ignored; we only measure
/// reachability and latency, not security.
struct TLSProbe: ReachabilityProbe {
    let host: String
    let port: UInt16

    func probeOnce(timeout: Double) async -> ProbeResult {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, _, complete in complete(true) },
            DispatchQueue.global())
        let params = NWParameters(tls: tls)
        params.prohibitExpensivePaths = false
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .https,
            using: params)
        let queue = DispatchQueue(label: "blipsy.tlsprobe")
        let start = DispatchTime.now()

        return await withCheckedContinuation { continuation in
            let guardOnce = ResumeGuard()
            func finish(_ result: ProbeResult) {
                guard guardOnce.claim() else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let rtt = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
                    finish(ProbeResult(success: true, rtt: rtt))
                case .failed, .cancelled:
                    finish(ProbeResult(success: false, rtt: nil))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(ProbeResult(success: false, rtt: nil))
            }
        }
    }
}
