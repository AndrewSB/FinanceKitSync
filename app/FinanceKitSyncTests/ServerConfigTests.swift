//
//  ServerConfigTests.swift
//  FinanceKitSyncTests
//
//  URL validation is the app's only guard against sending financial data over
//  a plaintext connection, so it gets tested like one.
//
import Testing
import Foundation
@testable import FinanceKitSync

@Suite("Server URL validation")
struct ServerConfigTests {

    @Test("accepts https URLs", arguments: [
        "https://box.tail590aa.ts.net",
        "https://box.tail590aa.ts.net:8443",
        "https://example.com/sync",
        "https://192.0.2.10:8501",
        "HTTPS://EXAMPLE.COM",          // scheme comparison is case-insensitive
    ])
    func acceptsHTTPS(input: String) {
        #expect(ServerConfig.validate(input) != nil, "should accept \(input)")
    }

    @Test("rejects anything that isn't https", arguments: [
        "http://example.com",           // the important one
        "ftp://example.com",
        "file:///etc/passwd",
        "example.com",                  // no scheme
        "https://",                     // no host
        "",
        "   ",
        "not a url at all",
    ])
    func rejectsNonHTTPS(input: String) {
        #expect(ServerConfig.validate(input) == nil, "should reject \(input)")
    }

    @Test("strips trailing slashes so path joining stays correct")
    func stripsTrailingSlashes() {
        // Without this, appendingPathComponent would produce a double slash and
        // some servers 404 on it.
        #expect(ServerConfig.validate("https://example.com/")?.absoluteString == "https://example.com")
        #expect(ServerConfig.validate("https://example.com///")?.absoluteString == "https://example.com")
    }

    @Test("trims surrounding whitespace")
    func trimsWhitespace() {
        // Pasting from a terminal or a password manager commonly brings a
        // trailing newline along.
        #expect(ServerConfig.validate("  https://example.com  ") != nil)
        #expect(ServerConfig.validate("https://example.com\n") != nil)
    }

    @Test("preserves the port")
    func preservesPort() {
        // Tailscale Funnel hands out non-443 ports, so dropping this would
        // break the documented setup.
        #expect(ServerConfig.validate("https://box.tail590aa.ts.net:8443")?.port == 8443)
    }
}
