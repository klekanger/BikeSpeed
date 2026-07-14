import Foundation
import SwiftData
import Testing
@testable import BikeSpeed

@Suite("TripDataStack", .tags(.persistence))
@MainActor
struct TripDataStackTests {

    private func trips(in stack: TripDataStack) throws -> [StoredTrip] {
        try stack.container.mainContext.fetch(
            FetchDescriptor<StoredTrip>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        )
    }

    // MARK: - Saving

    @Test
    func savingATripMakesItFetchable() async throws {
        let stack = try makeStack()
        let entry = makeEntry()

        try await stack.save(entry, altitudeProfile: makeProfile(), route: makeRoute())

        let saved = try trips(in: stack)
        #expect(saved.count == 1)
        #expect(saved.first?.id == entry.id)
    }

    @Test
    func aSavedTripCarriesItsTrackAndItsProfile() async throws {
        let stack = try makeStack()
        let entry = makeEntry()
        let route = makeRoute(count: 5)
        let profile = makeProfile(count: 4)

        try await stack.save(entry, altitudeProfile: profile, route: route)

        let trip = try #require(try trips(in: stack).first)
        let storedRoute = try TripPayloadCoder.decode([RouteSample].self, from: #require(trip.routeData))
        let storedProfile = try TripPayloadCoder.decode([AltitudeSample].self, from: #require(trip.altitudeData))
        #expect(storedRoute == route, "a track must round-trip sample for sample — it is the ride's map")
        #expect(storedProfile == profile)
    }

    /// "An empty track is not a track." The old `RouteFileStore.save` wrote no file for an empty route; the
    /// blob equivalent is to leave the column nil, so `TripLogDetailView` can keep telling "no track
    /// recorded" apart from "a track of nothing".
    @Test(.tags(.edgeCase))
    func savingATripWithNoRouteStoresNoRouteBlob() async throws {
        let stack = try makeStack()

        try await stack.save(makeEntry(), altitudeProfile: [], route: [])

        let trip = try #require(try trips(in: stack).first)
        #expect(trip.routeData == nil)
        #expect(trip.altitudeData == nil)
    }

    /// The dirty clock a future sync reads. Nothing consumes it today, which is exactly why it needs a test —
    /// a field nobody reads is a field that silently stops being written.
    @Test
    func savingStampsUpdatedAtAndLeavesTheSyncFieldsClear() async throws {
        let stack = try makeStack()
        let before = Date()

        try await stack.save(makeEntry(), altitudeProfile: [], route: [])

        let trip = try #require(try trips(in: stack).first)
        #expect(trip.updatedAt >= before)
        #expect(trip.syncedAt == nil, "a freshly saved trip owes the server everything")
        #expect(trip.deletedAt == nil)
        #expect(trip.remoteID == nil)
    }

    // MARK: - Deleting

    /// The bug class that `TripLogStore.reapOrphanedRoutes()` existed to sweep up simply cannot occur now:
    /// the track is a column of the row, so it dies with it. This test is what pins that.
    @Test
    func deletingATripTakesItsTrackWithIt() async throws {
        let stack = try makeStack()
        let entry = makeEntry()
        try await stack.save(entry, altitudeProfile: makeProfile(), route: makeRoute())
        let trip = try #require(try trips(in: stack).first)

        await stack.delete([trip])

        #expect(try trips(in: stack).isEmpty)
        let payloads = try await stack.repository.payloads(for: entry.id)
        #expect(payloads.routeData == nil, "the track must not outlive the trip that owned it")
        #expect(payloads.altitudeData == nil)
    }

    @Test
    func deletingATripLeavesTheOthersAlone() async throws {
        let stack = try makeStack()
        let keep = makeEntry(startDate: Date(timeIntervalSince1970: 1_000_000))
        let drop = makeEntry(startDate: Date(timeIntervalSince1970: 2_000_000))
        try await stack.save(keep, altitudeProfile: [], route: makeRoute())
        try await stack.save(drop, altitudeProfile: [], route: makeRoute())

        let victim = try #require(try trips(in: stack).first { $0.id == drop.id })
        await stack.delete([victim])

        let remaining = try trips(in: stack)
        #expect(remaining.map(\.id) == [keep.id])
        let payloads = try await stack.repository.payloads(for: keep.id)
        #expect(payloads.routeData != nil, "the surviving trip must keep its own track")
    }

    // MARK: - The sync seam

    /// Neither of these two tests is about the no-op engine. They exist so that a mutation path added to
    /// `TripDataStack` a year from now that forgets to notify the engine fails *here*, loudly, rather than
    /// silently failing to sync somebody's rides.
    @Test
    func savingATripNotifiesTheSyncEngine() async throws {
        let spy = SpyTripSyncEngine()
        let stack = try makeStack(sync: spy)
        let entry = makeEntry()

        try await stack.save(entry, altitudeProfile: [], route: [])

        #expect(spy.changed == [entry.id])
    }

    @Test
    func deletingATripNotifiesTheSyncEngine() async throws {
        let spy = SpyTripSyncEngine()
        let stack = try makeStack(sync: spy)
        let entry = makeEntry()
        try await stack.save(entry, altitudeProfile: [], route: [])
        let trip = try #require(try trips(in: stack).first)

        await stack.delete([trip])

        #expect(spy.deleted == [entry.id])
    }
}
