import Foundation
import Testing

@testable import BikeSpeed

/// Each test gets its own directory, so the suite stays safe under Swift Testing's parallel execution —
/// see `temporaryFileURL()` for why a unique *file* name is not enough once route tracks are in play.
@Suite(.tags(.persistence))
struct TripLogStoreTests {

    @Test
    func aSavedTripIsReadBackFromDisk() throws {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        store.save(makeEntry(distance: 12_400))

        let reloaded = TripLogStore(fileURL: url)

        #expect(reloaded.entries.count == 1)
        expectClose(try #require(reloaded.entries.first).distance, 12_400)
    }

    /// Views bind to `entries` directly, so the store owns the ordering rather than every caller re-sorting.
    @Test
    func entriesAreKeptNewestFirst() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let older = makeEntry(startDate: Date(timeIntervalSince1970: 1_000))
        let newer = makeEntry(startDate: Date(timeIntervalSince1970: 2_000))

        store.save(older)
        store.save(newer)

        #expect(store.entries.map(\.id) == [newer.id, older.id])
    }

    @Test
    func deletingByIdRemovesOnlyThatTrip() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let keep = makeEntry(distance: 1_000)
        let drop = makeEntry(distance: 2_000)
        store.save(keep)
        store.save(drop)

        store.delete(id: drop.id)

        #expect(store.entries.map(\.id) == [keep.id])
        #expect(TripLogStore(fileURL: url).entries.map(\.id) == [keep.id], "the deletion must reach disk")
    }

    @Test
    func deletingByOffsetRemovesTheRowTheUserSwiped() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let first = makeEntry(startDate: Date(timeIntervalSince1970: 2_000))
        let second = makeEntry(startDate: Date(timeIntervalSince1970: 1_000))
        store.save(second)
        store.save(first) // newest-first, so `first` is at index 0

        store.delete(at: IndexSet(integer: 0))

        #expect(store.entries.map(\.id) == [second.id])
    }

    @Test
    func anAbsentLogFileStartsEmptyRatherThanFailing() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        #expect(store.entries.isEmpty)
    }

    /// **The migration guard.**
    ///
    /// `TripLogStore.load()` falls back to `[]` when decoding throws — and the next save then writes that
    /// empty array over the user's history, permanently. So a `TripLogEntry` schema change must never make
    /// an existing file undecodable: new fields have to be optional.
    ///
    /// This fixture is JSON as written by the v1.1 app. It must keep decoding, untouched, for as long as
    /// anyone might still have a trip log on disk.
    @Test(.tags(.edgeCase))
    func aTripLogWrittenByTheCurrentSchemaStillDecodes() throws {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let legacyJSON = """
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
        try Data(legacyJSON.utf8).write(to: url)

        let store = TripLogStore(fileURL: url)

        let entry = try #require(store.entries.first, "a v1.1 trip log must survive every later schema change")
        expectClose(entry.distance, 12_400)
        expectClose(entry.maxSpeed, 11.4, within: 0.01)
        #expect(entry.altitudeProfile.count == 2)
        #expect(entry.totalAscent == nil, "a trip recorded before v2 genuinely has no ascent figure")
        #expect(entry.totalDescent == nil)
    }

    // MARK: - Route tracks

    /// Routes live one file per trip rather than inside `TripLogEntry`, so the round-trip has to be pinned
    /// separately from the entry's — nothing about saving a trip implies its track went with it.
    @Test
    func aSavedRouteIsReadBackFromDisk() throws {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let entry = makeEntry()
        store.save(entry)
        store.saveRoute(makeRoute(), for: entry.id)

        let route = try #require(TripLogStore(fileURL: url).route(for: entry.id))

        #expect(route.count == 3)
        expectClose(try #require(route.first).latitude, 59.9139, within: 0.000_001)
        expectClose(try #require(route.last).altitude ?? .nan, 102, within: 0.01)
    }

    /// A trip whose track was never recorded — every trip saved before this feature shipped — has to read
    /// back as "no route", not as an error and not as an empty ride.
    @Test
    func aTripWithNoRouteFileReadsBackAsNil() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let entry = makeEntry()
        store.save(entry)

        #expect(store.route(for: entry.id) == nil)
    }

    @Test
    func deletingATripByIdDeletesItsRouteToo() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let keep = makeEntry()
        let drop = makeEntry()
        store.save(keep)
        store.save(drop)
        store.saveRoute(makeRoute(), for: keep.id)
        store.saveRoute(makeRoute(), for: drop.id)

        store.delete(id: drop.id)

        #expect(store.route(for: drop.id) == nil, "a deleted trip must not leave its track behind on disk")
        #expect(store.route(for: keep.id) != nil, "and must take only its own")
    }

    /// The swipe-to-delete path is a separate method from `delete(id:)`, and a route file orphaned here
    /// would never be collected — the id that named it is gone with the entry.
    @Test
    func deletingATripByOffsetDeletesItsRouteToo() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let older = makeEntry(startDate: Date(timeIntervalSince1970: 1_000))
        let newer = makeEntry(startDate: Date(timeIntervalSince1970: 2_000))
        store.save(older)
        store.save(newer) // newest-first, so `newer` is at index 0
        store.saveRoute(makeRoute(), for: older.id)
        store.saveRoute(makeRoute(), for: newer.id)

        store.delete(at: IndexSet(integer: 0))

        #expect(store.route(for: newer.id) == nil)
        #expect(store.route(for: older.id) != nil)
    }

    /// An empty track is not a track. A `[]` file on disk would make `route(for:)` answer "yes, a route —
    /// with no points in it", and every caller would then have to re-check what the store already knew.
    @Test
    func anEmptyRouteWritesNoFile() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let entry = makeEntry()
        store.save(entry)

        store.saveRoute([], for: entry.id)

        #expect(store.route(for: entry.id) == nil)
    }

    /// **The leak guard.** The log is the only thing that knows which trips exist, and `load()` falls back
    /// to `[]` when it won't decode (see the migration guard above) — the next `persist()` then makes that
    /// permanent, taking every id that named a route file with it. Nothing could ever reach those files
    /// again, so they'd sit in Application Support for the life of the install, growing with each ride.
    @Test(.tags(.edgeCase))
    func aRouteFileWithNoTripIsReapedAtLoad() {
        let url = temporaryFileURL()
        defer { removeLog(at: url) }

        let store = TripLogStore(fileURL: url)
        let kept = makeEntry()
        store.save(kept)
        store.saveRoute(makeRoute(), for: kept.id)
        // A track whose trip the log does not know about — what a wiped or half-written log leaves behind.
        let orphan = UUID()
        store.saveRoute(makeRoute(), for: orphan)

        let reloaded = TripLogStore(fileURL: url)

        #expect(reloaded.route(for: orphan) == nil, "a track whose trip is gone must not outlive it")
        #expect(reloaded.route(for: kept.id) != nil, "and a live trip must keep its own")
    }

    // MARK: - Helpers

    private func makeRoute() -> [RouteSample] {
        (0..<3).map { index in
            RouteSample(
                latitude: 59.9139 + Double(index) * 0.001,
                longitude: 10.7522,
                altitude: 100 + Double(index),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
    }

    /// Removes the whole per-test directory, not just the log file — the store keeps route tracks in a
    /// `Routes/` folder beside the log.
    private func removeLog(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Each test gets a log in a directory of its own. A shared directory would not do: the store derives
    /// its `Routes/` folder from the log's *parent*, so tests sharing a parent would share a route folder
    /// and, under parallel execution, delete each other's tracks.
    private func temporaryFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TripLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("TripLog.json")
    }

    private func makeEntry(
        startDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        distance: Double = 10_000
    ) -> TripLogEntry {
        TripLogEntry(
            id: UUID(),
            startDate: startDate,
            duration: 1_800,
            distance: distance,
            averageSpeed: 6.8,
            maxSpeed: 11.4,
            altitudeProfile: [],
            totalAscent: nil,
            totalDescent: nil
        )
    }
}
