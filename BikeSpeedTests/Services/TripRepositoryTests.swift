import Foundation
import Testing
@testable import BikeSpeed

@Suite("TripRepository", .tags(.persistence))
@MainActor
struct TripRepositoryTests {

    /// The property `TripLogDetailView` depends on: a trip's payloads are reachable **off the main actor**,
    /// as bytes, so the O(samples) decode and the GPX render that follow can happen off the run loop. That a
    /// `@ModelActor` can be awaited from here at all is the thing being pinned.
    @Test
    func payloadsAreReadableOffTheMainActor() async throws {
        let stack = try makeStack()
        let entry = makeEntry()
        let route = makeRoute(count: 4)
        try await stack.save(entry, altitudeProfile: makeProfile(), route: route)

        let payloads = try await stack.repository.payloads(for: entry.id)

        let decoded = try TripPayloadCoder.decode([RouteSample].self, from: #require(payloads.routeData))
        #expect(decoded == route)
        #expect(payloads.altitudeData != nil)
    }

    @Test(.tags(.edgeCase))
    func payloadsForATripWithNoTrackAreNil() async throws {
        let stack = try makeStack()
        let entry = makeEntry()
        try await stack.save(entry, altitudeProfile: [], route: [])

        let payloads = try await stack.repository.payloads(for: entry.id)

        #expect(payloads.routeData == nil)
        #expect(payloads.altitudeData == nil)
    }

    @Test(.tags(.edgeCase))
    func payloadsForATripThatIsNotThereAreNil() async throws {
        let stack = try makeStack()

        let payloads = try await stack.repository.payloads(for: UUID())

        #expect(payloads.routeData == nil)
    }

    @Test
    func existingIDsReportsWhatIsInTheStore() async throws {
        let stack = try makeStack()
        let first = makeEntry(startDate: Date(timeIntervalSince1970: 1_000_000))
        let second = makeEntry(startDate: Date(timeIntervalSince1970: 2_000_000))
        try await stack.save(first, altitudeProfile: [], route: [])
        try await stack.save(second, altitudeProfile: [], route: [])

        let ids = try await stack.repository.existingIDs()

        #expect(ids == [first.id, second.id])
    }
}
