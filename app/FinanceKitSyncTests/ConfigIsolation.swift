//
//  ConfigIsolation.swift
//  FinanceKitSyncTests
//
//  ServerConfig is process-global (UserDefaults + Keychain), and Swift Testing
//  runs suites in parallel. Two tests each setting and clearing the server
//  config clobber each other — which is exactly what happened: a test asserting
//  "the engine skips" saw .notConfigured because a concurrent test had just
//  cleared the config out from under it.
//
//  `.serialized` doesn't help: it only orders tests *within* one suite. Every
//  test that touches ServerConfig must go through `withConfig` instead.
//
import Foundation
@testable import FinanceKitSync

/// A mutex that can be held across `await`.
///
/// Not an NSLock (unavailable from async contexts, since a suspended task can
/// resume on a different thread), and not a bare actor either — actors are
/// reentrant at suspension points, so an actor method wrapping an async body
/// would let a second caller in the moment the first awaits. This queues
/// waiters explicitly instead.
actor AsyncMutex {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            // Hand ownership straight to the next waiter; isHeld stays true.
            waiters.removeFirst().resume()
        }
    }
}

enum ConfigIsolation {
    private static let mutex = AsyncMutex()

    /// Runs `body` with the given server config applied, holding a global lock
    /// for the duration and restoring the previous config afterwards.
    ///
    /// Pass nil for both to exercise the unconfigured path.
    static func withConfig<T>(
        url: URL?, token: String?, _ body: () async throws -> T
    ) async rethrows -> T {
        await mutex.lock()
        let savedURL = ServerConfig.baseURLString
        let savedToken = ServerConfig.token

        ServerConfig.setBaseURL(url)
        ServerConfig.setToken(token)

        // Restore and release even when body throws. `defer` can't await, so
        // the unlock is dispatched into a detached task — mutex state is actor
        // isolated, so ordering stays correct.
        defer {
            ServerConfig.setBaseURL(ServerConfig.validate(savedURL))
            ServerConfig.setToken(savedToken)
            Task { await mutex.unlock() }
        }
        return try await body()
    }
}
