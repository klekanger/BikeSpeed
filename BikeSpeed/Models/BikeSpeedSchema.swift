import Foundation
import SwiftData

/// V1 is the schema the JSON trip log was imported into.
///
/// **When V2 arrives**: copy the *current* `StoredTrip` source into a `BikeSpeedSchemaV2` enum (renaming
/// the enum, not the class), evolve the top-level `StoredTrip`, and add a `MigrationStage` below. A
/// lightweight stage covers adding an optional attribute; anything that reshapes existing data needs
/// `.custom(willMigrate:didMigrate:)`.
enum BikeSpeedSchemaV1: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    nonisolated static var models: [any PersistentModel.Type] { [StoredTrip.self] }
}

/// Deliberately empty, and present from the first byte ever written. An app that ships unversioned and
/// *then* needs a migration has to guess what its original schema was; this one never will.
enum BikeSpeedMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] { [BikeSpeedSchemaV1.self] }
    nonisolated static var stages: [MigrationStage] { [] }
}

nonisolated enum TripModelContainer {
    static var schema: Schema { Schema(versionedSchema: BikeSpeedSchemaV1.self) }

    /// The CloudKit container every rider's trips mirror to — private database, so a trip follows the user's
    /// iCloud account across their devices and nobody else's.
    ///
    /// **Derived from the bundle id, never hardcoded.** `BikeSpeed.entitlements` names the container as
    /// `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`, which Xcode expands to `iCloud.<bundle id>`; this computes the
    /// identical string at runtime from `Bundle.main.bundleIdentifier`, so the two can't drift. A fork gets a
    /// working container by changing only its team and bundle id — no `lekanger`-specific string to hunt down.
    /// See the README's "Running your own copy".
    static let cloudKitContainerID: String = {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            preconditionFailure("No bundle identifier — cannot derive the CloudKit container id")
        }
        return "iCloud.\(bundleID)"
    }()

    /// The app's real store, mirrored to the user's private iCloud database.
    ///
    /// `NSPersistentCloudKitContainer` still opens the local store when the user is signed out — mirroring
    /// stays dormant until an account appears — so this doesn't throw for the no-account case. It throws
    /// only on genuine misprovisioning (missing entitlement, unprovisioned container id), a fatal build defect.
    static func app() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(
            for: schema,
            migrationPlan: BikeSpeedMigrationPlan.self,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        )
    }

    /// For tests and previews. `isStoredInMemoryOnly` makes the suite safe under Swift Testing's parallel
    /// execution: every test gets its own store with no file to collide over — what the old `TripLogStoreTests`
    /// had to buy with a per-test temp directory.
    static func inMemory() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(
            for: schema,
            migrationPlan: BikeSpeedMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
