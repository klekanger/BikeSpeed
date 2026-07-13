import Foundation
import Testing

@testable import BikeSpeed

/// Each test gets its own file URL, so the suite stays safe under Swift Testing's parallel execution.
@Suite(.tags(.persistence))
struct TripLogStoreTests {

    @Test
    func aSavedTripIsReadBackFromDisk() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

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
        defer { try? FileManager.default.removeItem(at: url) }

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
        defer { try? FileManager.default.removeItem(at: url) }

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
        defer { try? FileManager.default.removeItem(at: url) }

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
        let store = TripLogStore(fileURL: temporaryFileURL())
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
        defer { try? FileManager.default.removeItem(at: url) }

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

    // MARK: - Helpers

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TripLog-\(UUID().uuidString).json")
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
