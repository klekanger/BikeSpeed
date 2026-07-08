import Combine
import Foundation

/// Persists completed trips as a single JSON array in Application Support (not Documents — the
/// app has no file-sharing entitlement, and Application Support is the idiomatic home for
/// app-managed data the user isn't meant to browse via the Files app).
///
/// `entries` is always kept newest-first, so views can bind to it directly without re-sorting.
@MainActor
final class TripLogStore: ObservableObject {
    @Published private(set) var entries: [TripLogEntry] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func save(_ entry: TripLogEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        entries = entries.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        persist()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? decoder.decode([TripLogEntry].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleDir = supportDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "BikeSpeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        return bundleDir.appendingPathComponent("TripLog.json")
    }
}
