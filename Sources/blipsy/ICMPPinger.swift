import Foundation
import Darwin

/// A minimal, blocking ICMP echo pinger built on a per-probe datagram socket
/// (`SOCK_DGRAM` + `IPPROTO_ICMP`), which does not require root on macOS.
///
/// Called off the main thread from `ICMPProbe`. One socket per probe keeps the
/// implementation simple and stateless; probes are infrequent (seconds apart).
enum ICMPPinger {

    static func ping(host: String, timeout: Double) -> ProbeResult {
        guard var addr = resolve(host) else {
            return ProbeResult(success: false, rtt: nil)
        }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            // Socket creation can fail if the process is sandboxed; treat as unreachable.
            return ProbeResult(success: false, rtt: nil)
        }
        defer { close(fd) }

        // Receive timeout so recv() doesn't block forever on a dropped packet.
        var tv = timeval()
        tv.tv_sec = Int(timeout)
        tv.tv_usec = suseconds_t((timeout - Double(Int(timeout))) * 1_000_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let identifier = UInt16.random(in: 0...UInt16.max)
        var packet = makeEchoRequest(identifier: identifier, sequence: 0)

        let start = DispatchTime.now()

        let sent = packet.withUnsafeMutableBytes { raw -> Int in
            withUnsafePointer(to: &addr) { addrPtr -> Int in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent > 0 else { return ProbeResult(success: false, rtt: nil) }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received > 0 else {
            // Timed out (EAGAIN/EWOULDBLOCK) or error → counts as a dropped packet.
            return ProbeResult(success: false, rtt: nil)
        }

        let rtt = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        // Depending on the platform the reply may or may not carry the IPv4 header.
        var offset = 0
        if (buffer[0] >> 4) == 4 {                 // IPv4 header present
            offset = Int(buffer[0] & 0x0F) * 4
        }
        guard received > offset else { return ProbeResult(success: false, rtt: nil) }

        let icmpType = buffer[offset]
        // 0 == echo reply. The kernel demuxes datagram ICMP replies to this
        // socket by its identifier, so a reply here is ours.
        return icmpType == 0 ? ProbeResult(success: true, rtt: rtt)
                             : ProbeResult(success: false, rtt: nil)
    }

    // MARK: - Helpers

    private static func resolve(_ host: String) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else {
            return nil
        }
        defer { freeaddrinfo(info) }
        guard let sa = info.pointee.ai_addr, info.pointee.ai_family == AF_INET else {
            return nil
        }
        var addr = sockaddr_in()
        memcpy(&addr, sa, MemoryLayout<sockaddr_in>.size)
        return addr
    }

    private static func makeEchoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var p: [UInt8] = []
        p.append(8)                                   // type: echo request
        p.append(0)                                   // code
        p.append(0); p.append(0)                      // checksum placeholder
        p.append(UInt8(identifier >> 8)); p.append(UInt8(identifier & 0xFF))
        p.append(UInt8(sequence >> 8));   p.append(UInt8(sequence & 0xFF))
        p.append(contentsOf: Array("blipsy-ping-payload-0123456789ABCDEF".utf8))

        let checksum = internetChecksum(p)
        p[2] = UInt8(checksum >> 8)
        p[3] = UInt8(checksum & 0xFF)
        return p
    }

    /// Standard 16-bit one's-complement Internet checksum (RFC 1071).
    private static func internetChecksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < data.count {
            sum &+= (UInt32(data[i]) << 8) | UInt32(data[i + 1])
            i += 2
        }
        if i < data.count {
            sum &+= UInt32(data[i]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }
}
