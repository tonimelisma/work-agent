import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// REQ: FR-082 — deny private/link-local/metadata IPs *after* DNS resolution (SSRF).
// A hostname that looks public can still resolve to an internal address; the check
// has to happen on the resolved IP, not the hostname string.
public enum NetworkSafety {
    public static func assertPublicHost(_ host: String) async throws {
        let addresses = try await resolve(host)
        guard !addresses.isEmpty else { throw FetchURLError.disallowedHost(host) }
        for address in addresses where !isPublic(address) {
            throw FetchURLError.disallowedHost(host)
        }
    }

    // `getaddrinfo` blocks on a real DNS round-trip; dispatched off the cooperative
    // thread pool so it can't starve other structured-concurrency work while it waits.
    private static func resolve(_ host: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    continuation.resume(returning: try resolveBlocking(host))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func resolveBlocking(_ host: String) throws -> [String] {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
            ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let firstResult = result else { return [] }
        defer { freeaddrinfo(firstResult) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = firstResult
        while let info = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                info.pointee.ai_addr, info.pointee.ai_addrlen,
                &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST
            ) == 0 {
                let terminator = buffer.firstIndex(of: 0) ?? buffer.endIndex
                let bytes = buffer[..<terminator].map { UInt8(bitPattern: $0) }
                addresses.append(String(decoding: bytes, as: UTF8.self))
            }
            current = info.pointee.ai_next
        }
        return addresses
    }

    private static func isPublic(_ address: String) -> Bool {
        if address.contains(":") { return isPublicIPv6(address) }
        return isPublicIPv4(address)
    }

    private static func isPublicIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let (a, b) = (parts[0], parts[1])
        if a == 0 { return false }                          // 0.0.0.0/8
        if a == 10 { return false }                          // 10.0.0.0/8
        if a == 127 { return false }                         // 127.0.0.0/8 loopback
        if a == 169, b == 254 { return false }                // 169.254.0.0/16 link-local + metadata
        if a == 172, (16 ... 31).contains(b) { return false }  // 172.16.0.0/12
        if a == 192, b == 168 { return false }                 // 192.168.0.0/16
        if a >= 224 { return false }                          // multicast/reserved
        return true
    }

    private static func isPublicIPv6(_ address: String) -> Bool {
        let normalized = address.lowercased()
        if normalized == "::1" { return false }                // loopback
        if normalized.hasPrefix("fe80") { return false }        // link-local
        if normalized.hasPrefix("fc") || normalized.hasPrefix("fd") { return false } // ULA
        if normalized.hasPrefix("::ffff:") {                    // IPv4-mapped
            return isPublicIPv4(String(normalized.dropFirst("::ffff:".count)))
        }
        return true
    }
}
