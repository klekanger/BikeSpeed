import Foundation
import SwiftData
import Testing
@testable import BikeSpeed

@Suite("StoredTrip", .tags(.persistence))
@MainActor
struct StoredTripTests {

    @Test
    func aSavedTripIsReadBack() throws {
        let stack = try makeStack()
        let id = UUID()
        stack.container.mainContext.insert(StoredTrip(
            id: id,
            startDate: Date(timeIntervalSince1970: 1_760_000_000),
            duration: 1800,
            distance: 12_400,
            averageSpeed: 6.8,
            maxSpeed: 11.4,
            totalAscent: 312,
            totalDescent: 296,
            altitudeData: nil,
            routeData: nil,
            updatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        ))

        let trips = try stack.container.mainContext.fetch(FetchDescriptor<StoredTrip>())
        let trip = try #require(trips.first)
        #expect(trip.id == id)
        expectClose(trip.distance, 12_400)
        expectClose(trip.maxSpeed, 11.4, within: 0.01)
        expectClose(trip.totalAscent ?? 0, 312)
    }

    /// The scalar view of a row — what `TripLogSummary` reduces and what the list draws. It must not reach
    /// for a payload; see `StoredTrip.entry`.
    @Test
    func aTripConvertsToTheDomainEntry() async throws {
        let stack = try makeStack()
        let entry = makeEntry()
        try await stack.save(entry, altitudeProfile: makeProfile(), route: makeRoute())

        let trip = try #require(try stack.container.mainContext.fetch(FetchDescriptor<StoredTrip>()).first)
        #expect(trip.entry == entry)
    }

    /// **The invariant test.** CloudKit mirroring refuses a schema with unique constraints, non-optional
    /// attributes lacking defaults, or relationships without inverses — and it validates that at container
    /// build time, entitlement or no entitlement. So this genuinely fails if someone adds an
    /// `@Attribute(.unique)`, a bare `var name: String`, or a relationship to `StoredTrip`.
    ///
    /// Without it, "CloudKit-ready" is a comment in a file. With it, breaking it fails the build — which is
    /// the whole reason the model is shaped the way it is.
    @Test(.tags(.edgeCase))
    func theSchemaIsCloudKitCompatible() throws {
        let schema = TripModelContainer.schema
        #expect(throws: Never.self) {
            try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .private("iCloud.lekanger.BikeSpeed")
                )
            )
        }
    }

    /// A corollary of the above, asserted directly on the schema so the *reason* a violation fails is legible
    /// rather than buried in a Core Data error string.
    @Test(.tags(.edgeCase))
    func theSchemaCarriesNoUniqueConstraintsAndNoRelationships() throws {
        let entity = try #require(TripModelContainer.schema.entities.first { $0.name == "StoredTrip" })
        #expect(entity.uniquenessConstraints.isEmpty, "CloudKit mirroring rejects unique constraints outright")
        #expect(entity.relationships.isEmpty, "a track is a blob, not thousands of child CKRecords")

        let undefaulted = entity.attributes.filter { !$0.isOptional && $0.defaultValue == nil }
        #expect(undefaulted.isEmpty, "CloudKit requires every non-optional attribute to have a default")
    }
}
