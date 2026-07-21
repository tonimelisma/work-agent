import Foundation
import Testing
@testable import ToolKitWeb

// REQ: FR-082 — deny private/link-local/metadata IPs after DNS resolution (SSRF).

@Test("Loopback and link-local addresses are rejected")
func loopbackRejected() async throws {
    await #expect(throws: FetchURLError.disallowedHost("localhost")) {
        try await NetworkSafety.assertPublicHost("localhost")
    }
}

@Test("The cloud metadata address is rejected")
func metadataAddressRejected() async throws {
    await #expect(throws: FetchURLError.disallowedHost("169.254.169.254")) {
        try await NetworkSafety.assertPublicHost("169.254.169.254")
    }
}

@Test("A literal private IPv4 address is rejected without a DNS lookup")
func literalPrivateIPRejected() async throws {
    await #expect(throws: FetchURLError.disallowedHost("10.0.0.5")) {
        try await NetworkSafety.assertPublicHost("10.0.0.5")
    }
}

@Test("A literal public IPv4 address passes")
func literalPublicIPAllowed() async throws {
    try await NetworkSafety.assertPublicHost("93.184.216.34")
}
