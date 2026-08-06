//
//  LogStore.swift
//  FinanceKitSync
//
//  A small bounded log the user can read and share when something goes wrong.
//  Persisted to Application Support so a background run's output survives until
//  the app is next opened.
//
import Foundation

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let message: String

    init(date: Date = Date(), message: String) {
        self.id = UUID()
        self.date = date
        self.message = message
    }
}

/// Background-safe entry point. The sync engine runs off the main actor and
/// logs from there; this hops for it so callers don't have to think about it.
enum Log {
    static func append(_ message: String) {
        Task { @MainActor in LogStore.shared.append(message) }
    }
}

@MainActor
@Observable
final class LogStore {
    static let shared = LogStore()

    /// Kept small on purpose: this is a debugging aid, not an audit trail, and
    /// it is written from background tasks where I/O should stay cheap.
    private static let maxEntries = 500
    private static let fileName = "log.json"

    private(set) var entries: [LogEntry] = []

    private init() {
        entries = Self.load()
    }

    func append(_ message: String) {
        entries.append(LogEntry(message: message))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    /// Plain-text rendering for the share sheet.
    func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        let header = """
        FinanceKitSync log
        Server: \(ServerConfig.displayHost)
        Exported: \(formatter.string(from: Date()))

        """
        return header + entries
            .map { "\(formatter.string(from: $0.date))  \($0.message)" }
            .joined(separator: "\n")
    }

#if DEBUG
    /// Replaces the log with fabricated entries for App Store screenshots.
    /// Deliberately does not persist — nothing invented should outlive the run.
    /// See `ScreenshotMode`. Debug builds only.
    func seedForScreenshots(_ seeded: [LogEntry]) {
        entries = seeded
    }
#endif

    // MARK: - Persistence

    private static var fileURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent(fileName)
    }

    private static func load() -> [LogEntry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([LogEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
