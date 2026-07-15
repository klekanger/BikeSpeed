import Foundation
import SwiftData

/// The persisted form of a completed trip.
///
/// **Deliberately a different type from `TripLogEntry`.** The entry is the domain value: a `Codable`
/// struct that `TripLogSummary` reduces, that the list rows render, and that a future web service would
/// put on the wire unchanged. This is the row. Keeping them apart is what keeps `Models/` free of
/// `import SwiftData` everywhere else — and means the day a REST backend appears, the payload type
/// already exists.
///
/// **Every constraint here is a CloudKit constraint, not a SwiftData one.** Turning on
/// `ModelConfiguration(cloudKitDatabase:)` hands the schema to `NSPersistentCloudKitContainer`, which
/// refuses to mirror one that has unique constraints, non-optional attributes without defaults, or
/// relationships without inverses. So: no `@Attribute(.unique)`, every attribute defaulted, and no
/// relationships at all. We are not syncing today. We are making sure that turning it on is one line and
/// never a second data migration — `StoredTripTests.theSchemaIsCloudKitCompatible` fails the build if
/// anyone breaks that.
///
/// `nonisolated` because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin this class to
/// the main actor, and a main-actor `@Model` cannot be read or written inside a `@ModelActor` — which is
/// where the import runs and where the detail view's track is fetched from. Same tool `RouteFileStore`
/// and `GPXExporter` already reach for.
@Model
nonisolated final class StoredTrip {

    // MARK: - Identity and sync metadata
    //
    // Present from day one so that enabling sync is never a schema migration. Nothing writes `deletedAt`,
    // `syncedAt` or `remoteID` yet; `TripDataStack` is the single seam that will.

    /// The trip's stable identity across devices and backends — the same UUID the JSON log used, so an
    /// imported trip keeps the id its route file was named with.
    ///
    /// **No `@Attribute(.unique)`**: CloudKit mirroring rejects unique constraints outright, so the store
    /// will happily accept a duplicate id. Deduplication is therefore the *application's* job — see
    /// `LegacyTripLogImporter`, which fetches the existing ids and filters against them rather than
    /// relying on the store to reject a collision.
    ///
    /// `.preserveValueOnDeletion` is what carries this id into a SwiftData History *tombstone* (iOS 18).
    /// Without it a `HistoryDelete` knows only an opaque `PersistentIdentifier`, and a future sync could
    /// see that *a* trip was deleted but not *which*. It costs nothing now and cannot be added later
    /// without a migration.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Last local mutation — the dirty clock. `syncedAt == nil || updatedAt > syncedAt` means "this row
    /// owes the server something". Stamped on insert; nothing edits a saved trip today.
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// Soft-delete tombstone. **Unwritten today** — `TripDataStack.delete` hard-deletes, because with no
    /// sync there is no peer that could miss the deletion, and a tombstone nobody reads is just a row that
    /// never goes away. The field exists so that the day sync ships, `delete` sets this instead of calling
    /// `context.delete`, and *nothing else changes*: the list's `@Query` already filters on it.
    var deletedAt: Date?

    /// When the server last acknowledged this row. Nil = never synced.
    var syncedAt: Date?

    /// A web service's own primary key, if it insists on assigning one. Free to carry now, impossible to
    /// add later without a migration.
    var remoteID: String?

    // MARK: - Trip data

    var startDate: Date = Date(timeIntervalSince1970: 0)
    var duration: TimeInterval = 0     // seconds, active only
    var distance: Double = 0           // meters
    var averageSpeed: Double = 0       // m/s
    var maxSpeed: Double = 0           // m/s
    /// Optional for the same reason it always was: a trip recorded without usable altitude has no answer to
    /// "how much did you climb", and 0 would call it flat. (That it also satisfies CloudKit is a bonus.)
    var totalAscent: Double?
    var totalDescent: Double?

    // MARK: - Payloads
    //
    // The *encoded value arrays*, not relationships. A 40 km ride is thousands of route samples; as a
    // to-many relationship that would be thousands of CKRecords for a single trip, against a CloudKit
    // operation cap of 400. As external storage it is one CKRecord with one CKAsset — and Core Data faults
    // the blob in only when the property is actually read, so the trip list never pays for a track it does
    // not draw. That is the same property the old file-per-route layout existed to buy, now for free.
    //
    // The encoding is `TripPayloadCoder`'s, which is byte-identical to what `Routes/<uuid>.json` held — so
    // the importer copies those files in as bytes rather than re-encoding them.

    /// The height profile: `[AltitudeSample]`, JSON.
    @Attribute(.externalStorage) var altitudeData: Data?

    /// The recorded track: `[RouteSample]`, JSON.
    @Attribute(.externalStorage) var routeData: Data?

    // MARK: - Indices
    //
    // The list sorts by `startDate`; everything else looks a trip up by `id`. `#Index` (iOS 18) makes both
    // an index seek rather than a table scan once the log holds years of rides. Note `#Index`, *not*
    // `#Unique` — see `id`.
    #Index<StoredTrip>([\.startDate], [\.id])

    init(
        id: UUID,
        startDate: Date,
        duration: TimeInterval,
        distance: Double,
        averageSpeed: Double,
        maxSpeed: Double,
        totalAscent: Double?,
        totalDescent: Double?,
        altitudeData: Data?,
        routeData: Data?,
        updatedAt: Date
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.distance = distance
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.totalAscent = totalAscent
        self.totalDescent = totalDescent
        self.altitudeData = altitudeData
        self.routeData = routeData
        self.updatedAt = updatedAt
    }
}

extension StoredTrip {
    /// Builds a row from a domain value plus its already-encoded payloads — the inverse of `entry`, kept
    /// beside it so the field-by-field mapping lives in exactly one place. `TripDataStack.save` and
    /// `TripRepository.insert` both go through here; adding a scalar to a trip then touches this init, the
    /// designated init, and `entry`, and nowhere else.
    convenience init(entry: TripLogEntry, altitudeData: Data?, routeData: Data?, updatedAt: Date) {
        self.init(
            id: entry.id,
            startDate: entry.startDate,
            duration: entry.duration,
            distance: entry.distance,
            averageSpeed: entry.averageSpeed,
            maxSpeed: entry.maxSpeed,
            totalAscent: entry.totalAscent,
            totalDescent: entry.totalDescent,
            altitudeData: altitudeData,
            routeData: routeData,
            updatedAt: updatedAt
        )
    }

    /// The row as the domain value the pure code speaks — `TripLogSummary`, the list rows, one day a REST
    /// payload.
    ///
    /// **Touches no blob**, which is the entire point: this runs once per visible row on every render of the
    /// trip list, and faulting a track in here is exactly what the old file-per-route layout was built to
    /// avoid. Do not "helpfully" fold the altitude profile back into it.
    var entry: TripLogEntry {
        TripLogEntry(
            id: id,
            startDate: startDate,
            duration: duration,
            distance: distance,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            totalAscent: totalAscent,
            totalDescent: totalDescent
        )
    }
}
