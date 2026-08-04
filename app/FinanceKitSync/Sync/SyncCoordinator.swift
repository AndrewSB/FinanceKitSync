//
//  SyncCoordinator.swift
//  FinanceKitSync
//
//  The observable layer between SyncEngine and the UI. Owns "am I syncing",
//  "what happened last time", and the counts the home screen shows.
//
import Foundation
import BackgroundTasks

@MainActor
@Observable
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    /// Registered in Info.plist under BGTaskSchedulerPermittedIdentifiers.
    static let refreshTaskIdentifier = "com.asb.FinanceKitSync.refresh"

    enum State: Equatable {
        case idle
        case syncing(progress: String)
    }

    private(set) var state: State = .idle
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?
    private(set) var lastSentCount: Int = 0
    private(set) var acknowledgedCount: Int = 0

    private let defaults = UserDefaults.standard
    private let lastSyncKey = "last_sync_date"
    private let lastErrorKey = "last_sync_error"

    private init() {
        lastSyncDate = defaults.object(forKey: lastSyncKey) as? Date
        lastError = defaults.string(forKey: lastErrorKey)
        refreshCounts()
    }

    var isSyncing: Bool {
        if case .syncing = state { return true }
        return false
    }

    func refreshCounts() {
        acknowledgedCount = SyncLedger.open()?.count() ?? 0
    }

    /// Runs one pass and folds the outcome into the published state.
    @discardableResult
    func syncNow() async -> SyncEngine.Outcome {
        guard !isSyncing else { return .skipped("already running") }
        state = .syncing(progress: "Starting…")

        let outcome = await SyncEngine.run { [weak self] message in
            Log.append(message)
            Task { @MainActor in
                guard let self, self.isSyncing else { return }
                self.state = .syncing(progress: message)
            }
        }

        state = .idle
        switch outcome {
        case .notConfigured:
            lastError = "No server configured."
        case .skipped(let reason):
            Log.append("skipped: \(reason)")
        case .success(let sent):
            lastSentCount = sent
            lastSyncDate = Date()
            lastError = nil
            defaults.set(lastSyncDate, forKey: lastSyncKey)
            defaults.removeObject(forKey: lastErrorKey)
        case .failure(let sent, let error):
            lastSentCount = sent
            lastError = error.localizedDescription
            defaults.set(lastError, forKey: lastErrorKey)
            // A partial success still moved the ledger forward, so record it.
            if sent > 0 {
                lastSyncDate = Date()
                defaults.set(lastSyncDate, forKey: lastSyncKey)
            }
        }
        refreshCounts()
        return outcome
    }

    /// Clears the ledger so the next run replays the full history.
    func resendEverything() {
        guard let ledger = SyncLedger.open() else {
            lastError = "The local ledger could not be opened."
            return
        }
        do {
            try ledger.reset()
            Log.append("ledger cleared — next sync will replay the full history")
            refreshCounts()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Background tasks

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier, using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                // Always reschedule first: if this run crashes or is killed for
                // running long, a follow-up is already on the books.
                self.scheduleBackgroundRefresh()

                let work = Task { await self.syncNow() }
                refreshTask.expirationHandler = { work.cancel() }
                let outcome = await work.value
                if case .failure = outcome {
                    refreshTask.setTaskCompleted(success: false)
                } else {
                    refreshTask.setTaskCompleted(success: true)
                }
            }
        }
    }

    func scheduleBackgroundRefresh() {
        guard ServerConfig.backgroundSyncEnabled, ServerConfig.isConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        // A floor, not a promise — iOS decides when this actually runs.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Log.append("could not schedule background refresh: \(error.localizedDescription)")
        }
    }
}
