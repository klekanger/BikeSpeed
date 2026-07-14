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

    /// The app's real store.
    ///
    /// `cloudKitDatabase: .none` today. The Pro tier flips this one argument to
    /// `.private("iCloud.lekanger.BikeSpeed")` and adds the project's first entitlements file — and that is
    /// the entire CloudKit change, because `StoredTrip` was built to satisfy the mirroring rules from day
    /// one. No code, no migration.
    static func app() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(
            for: schema,
            migrationPlan: BikeSpeedMigrationPlan.self,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        )
    }

    /// For tests and previews. `isStoredInMemoryOnly` is what makes the suite safe under Swift Testing's
    /// parallel execution: every test gets its own store with no file to collide over — the property the old
    /// `TripLogStoreTests` had to buy with a per-test temp directory.
    static func inMemory() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(
            for: schema,
            migrationPlan: BikeSpeedMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
