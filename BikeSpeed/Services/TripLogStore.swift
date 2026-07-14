import Foundation
import Observation

/// Persists completed trips as a single JSON array in Application Support (not Documents — the
/// app has no file-sharing entitlement, and Application Support is the idiomatic home for
/// app-managed data the user isn't meant to browse via the Files app).
///
/// `entries` is always kept newest-first, so views can bind to it directly without re-sorting.
///
/// Route tracks are deliberately *not* part of `TripLogEntry` and live one file per trip in `Routes/`.
/// `persist()` rewrites every entry as one JSON array on every save, so inlining a few hundred track
/// points per trip would make the log file grow without bound and rewrite all of it each time — and the
/// list view, which needs none of it, would decode the lot on launch. A route is read only when a single
/// trip's detail is opened, which is exactly when its own file is cheap to load.
@MainActor
@Observable
final class TripLogStore {
    private(set) var entries: [TripLogEntry] = []

    /// Deliberately `nonisolated` and public to the module: this is how `TripLogDetailView` reads a track
    /// off the main actor, which reading it *through* this `@MainActor` class could never be.
    @ObservationIgnored nonisolated let routes: RouteFileStore

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        let logURL = fileURL ?? Self.defaultFileURL()
        self.fileURL = logURL
        // Beside the log, wherever the log is — so an injected temp URL in a test takes its routes
        // with it and no test can see another's.
        self.routes = RouteFileStore(
            directory: logURL.deletingLastPathComponent().appendingPathComponent("Routes", isDirectory: true)
        )
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func save(_ entry: TripLogEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        delete(ids: offsets.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
    }

    func delete(id: UUID) {
        delete(ids: [id])
    }

    /// The one place a trip is removed — and therefore the one place that has to know a trip owns a
    /// track. The swipe and the detail-view button used to each drop their own entry and each remember
    /// to reap the route file separately; the next deletion path to be added would have forgotten, and
    /// the orphan is unreachable forever once the id that named it is gone with the entry.
    private func delete(ids: [UUID]) {
        let removing = Set(ids)
        entries.removeAll { removing.contains($0.id) }
        ids.forEach { routes.delete($0) }
        persist()
    }

    func saveRoute(_ route: [RouteSample], for id: UUID) {
        routes.save(route, for: id)
    }

    /// Convenience for callers already on the main actor — chiefly the tests. `TripLogDetailView` goes
    /// through `routes` directly instead, so the decode happens off the run loop.
    func route(for id: UUID) -> [RouteSample]? {
        routes.load(id)
    }

    private func load() {
        defer { reapOrphanedRoutes() }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? decoder.decode([TripLogEntry].self, from: data)) ?? []
    }

    /// The log is the authority on which trips exist, so anything in `Routes/` it doesn't name is dead.
    ///
    /// This is not belt-and-braces: `load()` above falls back to an empty array when the log won't decode
    /// — the migration gate `TripLogStoreTests` pins — and the next `persist()` writes that emptiness
    /// down for good, taking with it every id that named a route file. Without this, those files would sit
    /// in Application Support forever, growing with each ride, with no row left for the user to swipe.
    private func reapOrphanedRoutes() {
        routes.orphans(keeping: Set(entries.map(\.id)))
            .forEach { try? FileManager.default.removeItem(at: $0) }
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
