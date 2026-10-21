//
//  ServerConfig.swift
//  FinanceKitSync
//
//  Where the packets go: a base URL (not secret — it shows up in logs and the
//  UI) and a bearer token (secret — Keychain only).
//
import Foundation
import Security

enum ServerConfig {
    private static let baseURLKey = "server_base_url"
    private static let tokenAccount = "server_bearer_token"
    private static let backgroundSyncKey = "background_sync_enabled"
    private static let installAccount = "device_install_id"

    // MARK: - Install identity

    /// A random UUID minted on first use and kept for the life of this install,
    /// sent with every packet. FinanceKit IDs are device-local, so the server
    /// uses this to tell a phone that re-keyed its history from two phones
    /// syncing at once.
    ///
    /// ThisDeviceOnly and never synchronizable: it must not follow a backup or
    /// iCloud Keychain onto a new phone, or the new phone would pass for the old.
    static var deviceInstallID: String {
        if let existing = Keychain.read(installAccount) { return existing }
        let fresh = UUID().uuidString
        Keychain.write(installAccount, fresh,
                       accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        return fresh
    }

    // MARK: - Base URL

    /// Validates a user-entered base URL: https, with a host. A port is fine —
    /// Tailscale Funnel commonly hands out non-443 ports.
    ///
    /// Returns the normalized URL (trailing slashes stripped) or nil.
    static func validate(_ string: String) -> URL? {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// The configured base URL, or nil when unset or no longer valid.
    static var baseURL: URL? {
        guard let stored = UserDefaults.standard.string(forKey: baseURLKey),
              !stored.isEmpty else { return nil }
        return validate(stored)
    }

    /// The raw stored string, for pre-filling the settings field.
    static var baseURLString: String {
        UserDefaults.standard.string(forKey: baseURLKey) ?? ""
    }

    static func setBaseURL(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: baseURLKey)
        } else {
            UserDefaults.standard.removeObject(forKey: baseURLKey)
        }
    }

    // MARK: - Token

    /// In demo mode this is the demo server's token, so the engine and the
    /// settings form see a coherent (address, token) pair. The user's real
    /// token stays in the Keychain, untouched, for when the demo ends.
    static var token: String? {
        if DemoMode.isEnabled { return DemoMode.token }
        return Keychain.read(tokenAccount)
    }

    @discardableResult
    static func setToken(_ token: String?) -> Bool {
        Keychain.write(tokenAccount, token)
    }

    // MARK: - Derived

    /// Both halves present. The engine refuses to run otherwise — a packet sent
    /// without a token would just 401, and we'd rather say why up front.
    static var isConfigured: Bool {
        baseURL != nil && !(token ?? "").isEmpty
    }

    static var backgroundSyncEnabled: Bool {
        get {
            // Default on: the whole point is that it keeps up without being opened.
            UserDefaults.standard.object(forKey: backgroundSyncKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: backgroundSyncKey) }
    }

    /// Host (and port) for display. Never renders the token.
    static var displayHost: String {
        guard let url = baseURL, let host = url.host else { return "Not configured" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}
