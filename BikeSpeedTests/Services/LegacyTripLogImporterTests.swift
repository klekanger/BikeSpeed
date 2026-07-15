import Foundation
import SwiftData
import Testing
@testable import BikeSpeed

/// The highest-stakes suite in the app. Everything here stands between an existing rider and a lost history.
@Suite("LegacyTripLogImporter", .tags(.persistence))
@MainActor
struct LegacyTripLogImporterTests {

    private func trips(in stack: TripDataStack) throws -> [StoredTrip] {
        try stack.container.mainContext.fetch(
            FetchDescriptor<StoredTrip>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
    }

    private func importer(_ directory: URL, _ stack: TripDataStack) -> LegacyTripLogImporter {
        LegacyTripLogImporter(legacyDirectory: directory, repository: stack.repository)
    }

    /// **The fixture, verbatim from the old `TripLogStoreTests`.** This is JSON as written by the shipped
    /// v1.1 app: no `totalAscent`/`totalDescent` (they came in v2), and `altitudeProfile` still inline in the
    /// entry (it has since moved out to a payload blob). It must keep importing, untouched, for as long as
    /// anyone might still have a trip log on disk.
    private let v1_1Log = """
    [
      {
        "id": "9F0D6C1E-4B7A-4C2E-9E3A-1D5B6F8C7A21",
        "startDate": "2026-07-04T09:15:00Z",
        "duration": 1830,
        "distance": 12400,
        "averageSpeed": 6.8,
        "maxSpeed": 11.4,
        "altitudeProfile": [
          { "distance": 0, "altitude": 100 },
          { "distance": 25, "altitude": 103.5 }
        ]
      }
    ]
    """
    private let v1_1TripID = UUID(uuidString: "9F0D6C1E-4B7A-4C2E-9E3A-1D5B6F8C7A21")!

    // MARK: - The happy path

    @Test
    func aV1_1TripLogIsImported() async throws {
        let stack = try makeStack()
        let directory = try makeLegacyDirectory(log: v1_1Log)
        defer { removeDirectory(directory) }

        let outcome = try await importer(directory, stack).run()

        #expect(outcome == .imported(trips: 1, routes: 0))
        let trip = try #require(try trips(in: stack).first)
        #expect(trip.id == v1_1TripID)
        expectClose(trip.distance, 12_400)
        expectClose(trip.maxSpeed, 11.4, within: 0.01)

        // The inline profile became a payload blob, without losing a sample.
        let profile = try TripPayloadCoder.decode([AltitudeSample].self, from: #require(trip.altitudeData))
        #expect(profile.count == 2)
        expectClose(profile[1].altitude, 103.5, within: 0.01)
    }

    /// "We don't know" must survive the migration as something other than "it was flat". A pre-v2 trip has no
    /// ascent figure at all, and importing it as 0 would invent a fact and, worse, let it win a personal best.
    @Test(.tags(.edgeCase))
    func aTripLogWithNoAscentImportsWithNoAscent() async throws {
        let stack = try makeStack()
        let directory = try makeLegacyDirectory(log: v1_1Log)
        defer { removeDirectory(directory) }

        try await importer(directory, stack).run()

        let trip = try #require(try trips(in: stack).first)
        #expect(trip.totalAscent == nil)
        #expect(trip.totalDescent == nil)
    }

    /// Route files are carried across as **bytes**, not decoded and re-encoded. A re-encode is a chance to
    /// change the last digit of a coordinate or reorder a sample, and there is no reason to take it.
    @Test
    func routeFilesAreImportedByteForByte() async throws {
        let stack = try makeStack()
        let route = makeRoute(count: 4)
        let routeJSON = String(decoding: try TripPayloadCoder.encode(route), as: UTF8.self)
        let directory = try makeLegacyDirectory(log: v1_1Log, routes: [v1_1TripID: routeJSON])
        defer { removeDirectory(directory) }

        let outcome = try await importer(directory, stack).run()

        #expect(outcome == .imported(trips: 1, routes: 1))
        let trip = try #require(try trips(in: stack).first)
        #expect(trip.routeData == Data(routeJSON.utf8), "the track must arrive byte-identical")
        let decoded = try TripPayloadCoder.decode([RouteSample].self, from: #require(trip.routeData))
        #expect(decoded == route)
    }

    @Test(.tags(.edgeCase))
    func aTripWithNoRouteFileImportsWithNoTrack() async throws {
        let stack = try makeStack()
        let directory = try makeLegacyDirectory(log: v1_1Log)
        defer { removeDirectory(directory) }

        try await importer(directory, stack).run()

        let trip = try #require(try trips(in: stack).first)
        #expect(trip.routeData == nil, "every trip saved before route recording shipped has no track, and that is fine")
    }

    /// A trip that has not been ridden since 2026 has not *changed* since 2026. If the import stamped
    /// `updatedAt` with the migration date, a future sync would conclude the rider's entire back catalogue
    /// changed on the day they installed this update, and push all of it.
    @Test
    func importedTripsKeepTheirOriginalDates() async throws {
        let stack = try makeStack()
        let directory = try makeLegacyDirectory(log: v1_1Log)
        defer { removeDirectory(directory) }

        try await importer(directory, stack).run()

        let trip = try #require(try trips(in: stack).first)
        #expect(trip.updatedAt == trip.startDate)
        #expect(trip.syncedAt == nil)
    }

    // MARK: - Deleting the legacy files

    @Test
    func theLegacyFilesAreDeletedAfterAVerifiedImport() async throws {
        let stack = try makeStack()
        let routeJSON = String(decoding: try TripPayloadCoder.encode(makeRoute()), as: UTF8.self)
        let directory = try makeLegacyDirectory(log: v1_1Log, routes: [v1_1TripID: routeJSON])
        defer { removeDirectory(directory) }

        try await importer(directory, stack).run()

        #expect(!legacyLogExists(in: directory))
        let routesDirectory = directory.appendingPathComponent("Routes", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: routesDirectory.path))
    }

    @Test
    func anAbsentLogIsNothingToImport() async throws {
        let stack = try makeStack()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeDirectory(directory) }

        let outcome = try await importer(directory, stack).run()

        #expect(outcome == .nothingToImport)
        #expect(try trips(in: stack).isEmpty)
    }

    // MARK: - The two guards that matter

    /// **The most important test here.** `TripLogStore.load()` used to swallow a decode failure into `[]`, and
    /// the next save wrote that emptiness over the user's history for good. The importer must never inherit
    /// that: a log it cannot parse is a log it does not understand, and a log it does not understand is a log
    /// it does not delete. The rider gets their file back and a chance to recover it.
    @Test(.tags(.edgeCase))
    func anUnreadableLogIsNotDeleted() async throws {
        let stack = try makeStack()
        let directory = try makeLegacyDirectory(log: "{ this is not json")
        defer { removeDirectory(directory) }

        await #expect(throws: LegacyTripLogImporter.ImportError.logIsUnreadable) {
            try await importer(directory, stack).run()
        }

        #expect(legacyLogExists(in: directory), "a log we cannot parse is a log we must not throw away")
        #expect(try trips(in: stack).isEmpty)
    }

    /// A partial failure leaves the legacy files in place, so the next launch retries. That retry must not
    /// duplicate the rider's history — and there is no `@Attribute(.unique)` to stop it, because CloudKit
    /// forbids one. The id-keyed upsert in `TripRepository.insert` is the only defence, and this is what
    /// proves it works.
    @Test(.tags(.edgeCase))
    func reimportingDoesNotDuplicate() async throws {
        let stack = try makeStack()
        let directory = try makeLegacyDirectory(log: v1_1Log)
        defer { removeDirectory(directory) }

        try await importer(directory, stack).run()
        // The import deleted the log; put it back, as a restore-from-backup or a half-failed run would.
        try Data(v1_1Log.utf8).write(to: directory.appendingPathComponent("TripLog.json"))
        try await importer(directory, stack).run()

        #expect(try trips(in: stack).count == 1, "one ride, ridden once, however many times we import it")
    }

    /// An unparseable *route* is not an unparseable *log*. The trip itself is intact, and a ride recorded
    /// without its map is far better than a migration that refuses to run — the same call `RouteFileStore`
    /// already made.
    @Test(.tags(.edgeCase))
    func anUnreadableRouteFileCostsTheTrackButNotTheTrip() async throws {
        let stack = try makeStack()
        let directory = try makeLegacyDirectory(log: v1_1Log, routes: [v1_1TripID: "{ not a route"])
        defer { removeDirectory(directory) }

        let outcome = try await importer(directory, stack).run()

        #expect(outcome == .imported(trips: 1, routes: 0))
        let trip = try #require(try trips(in: stack).first)
        #expect(trip.routeData == nil)
        expectClose(trip.distance, 12_400, within: 0.01)
    }
}
