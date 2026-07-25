import Foundation

/// Moves the JSON trip log into SwiftData, once, and then removes it.
///
/// Directory and repository are injected, so a test drives this against a temp directory and an in-memory
/// store, never touching the real Application Support.
///
/// **Idempotency is state, not a flag.** Runs whenever `TripLog.json` still exists; a successful import deletes
/// it, so nothing is left to re-run — no `UserDefaults` boolean a restore-from-backup could reset while the
/// JSON came back alongside it. A *partial* failure leaves the file, and the retry is safe because
/// `TripRepository.insert` upserts on `id` — the only defence there is, since CloudKit forbids the
/// `@Attribute(.unique)` that would reject a duplicate.
nonisolated struct LegacyTripLogImporter {

    /// **Frozen.** What the app wrote up to v1.1; must keep decoding for as long as anyone might still have
    /// that file.
    ///
    /// Private to the importer rather than the live `TripLogEntry` on purpose: the live entry has since lost
    /// `altitudeProfile` to a payload blob, and sharing the type would have silently broken every existing
    /// user's import. A legacy format is a fact about the past; it doesn't get refactored.
    private struct LegacyTripLogEntry: Decodable {
        let id: UUID
        let startDate: Date
        let duration: TimeInterval
        let distance: Double
        let averageSpeed: Double
        let maxSpeed: Double
        let altitudeProfile: [AltitudeSample]?  // absent in the oldest files
        let totalAscent: Double?                // absent before v2
        let totalDescent: Double?
    }

    enum ImportError: Error, Equatable {
        /// The log exists but will not decode. **Nothing is deleted** — the single most important behaviour in
        /// this file. `TripLogStore.load()` used to do `(try? decode(...)) ?? []`, and the next `persist()`
        /// would write that emptiness over the user's history permanently. A log we can't parse is one we don't
        /// delete.
        case logIsUnreadable
        case verificationFailed(missing: [UUID])
    }

    enum Outcome: Equatable {
        /// No legacy log: a fresh install, or a previous import already finished the job.
        case nothingToImport
        case imported(trips: Int, routes: Int)
    }

    let legacyDirectory: URL
    let repository: TripRepository

    /// Where the JSON log lived: `Application Support/<bundle id>/`. Keyed off the bundle id exactly as
    /// `TripLogStore.defaultFileURL()` was, so it finds the file the shipped app wrote.
    static func applicationSupportDirectory() -> URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "BikeSpeed", isDirectory: true)
    }

    private var logURL: URL { legacyDirectory.appendingPathComponent("TripLog.json") }
    private var routesDirectory: URL { legacyDirectory.appendingPathComponent("Routes", isDirectory: true) }

    @discardableResult
    func run() async throws -> Outcome {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return .nothingToImport }

        guard let data = try? Data(contentsOf: logURL),
              let legacy = try? TripPayloadCoder.decode([LegacyTripLogEntry].self, from: data)
        else { throw ImportError.logIsUnreadable }

        // Route bytes are carried through untouched — decoded once to prove they parse, then stored exactly
        // as they were read. `routeSizes` is what the post-import verification checks against.
        var routeSizes: [UUID: Int] = [:]
        let importable: [ImportableTrip] = try legacy.map { entry in
            let routeData = routeBytes(for: entry.id)
            if let routeData { routeSizes[entry.id] = routeData.count }
            let profile = entry.altitudeProfile ?? []
            return ImportableTrip(
                entry: TripLogEntry(
                    id: entry.id,
                    startDate: entry.startDate,
                    duration: entry.duration,
                    distance: entry.distance,
                    averageSpeed: entry.averageSpeed,
                    maxSpeed: entry.maxSpeed,
                    totalAscent: entry.totalAscent,
                    totalDescent: entry.totalDescent
                ),
                altitudeData: profile.isEmpty ? nil : try TripPayloadCoder.encode(profile),
                routeData: routeData,
                // An imported trip hasn't been touched since it was ridden, so its last local mutation is when
                // it was recorded, not the migration day. Otherwise a future sync would conclude the rider's
                // whole back catalogue changed on install day and push all of it.
                updatedAt: entry.startDate
            )
        }

        try await repository.insert(importable)

        // Verify *from the store*, not from what we think we wrote.
        let ids = legacy.map(\.id)
        let stored = try await repository.routeByteCounts(for: ids)
        let missing = ids.filter { stored[$0] == nil }
        guard missing.isEmpty else { throw ImportError.verificationFailed(missing: missing) }
        let truncated = routeSizes.filter { stored[$0.key] != $0.value }.map(\.key)
        guard truncated.isEmpty else { throw ImportError.verificationFailed(missing: truncated) }

        // Verified. Only now.
        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.removeItem(at: routesDirectory)

        return .imported(trips: importable.count, routes: routeSizes.count)
    }

    /// Nil for a trip with no track — every trip saved before route recording shipped. A normal answer, not an
    /// error, as `RouteFileStore.load` treated it.
    ///
    /// A route file that exists but won't decode is also treated as "no track" rather than failing the whole
    /// import: the trip is intact, and a ride without its map beats a migration that refuses to run (the same
    /// judgement `RouteFileStore.save` made). The **log** is the opposite case — the user's entire history, and
    /// fatal.
    private func routeBytes(for id: UUID) -> Data? {
        let url = routesDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              (try? TripPayloadCoder.decode([RouteSample].self, from: data)) != nil
        else { return nil }
        return data
    }
}
