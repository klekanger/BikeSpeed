//
//  BikeSpeedApp.swift
//  BikeSpeed
//
//  Created by Kurt Lekanger on 04/07/2026.
//

import SwiftData
import SwiftUI

@main
struct BikeSpeedApp: App {
    @State private var locationManager: LocationManager
    @State private var addressLookupManager: AddressLookupManager
    @State private var settingsStore: SettingsStore
    @State private var tripManager: TripManager
    @State private var motionManager = MotionManager()
    @State private var stack: TripDataStack
    @State private var isShowingImportFailure = false

    /// Held, but neither `@State` nor in the environment: it is not observable and no view reads it —
    /// `TripManager` is its only consumer, and samples it directly. See `AltimeterManager`.
    private let altimeterManager: AltimeterManager

    init() {
        let locationManager = LocationManager()
        let settingsStore = SettingsStore()
        let altimeterManager = AltimeterManager()
        self.altimeterManager = altimeterManager
        _locationManager = State(initialValue: locationManager)
        _settingsStore = State(initialValue: settingsStore)
        _tripManager = State(initialValue: TripManager(locationManager: locationManager, altimeter: altimeterManager, settings: settingsStore))
        _addressLookupManager = State(initialValue: AddressLookupManager(locationManager: locationManager))

        // A store that will not open is not something the app can carry on without, and not something the
        // rider can act on — every trip they have ever saved lives in it. There is no honest degraded mode:
        // running on a throwaway in-memory store would silently accept rides and drop them at quit. Note the
        // legacy JSON is still on disk in this case, because `LegacyTripLogImporter` cannot have run without
        // a container to import *into*, and it deletes nothing until the import verifies.
        do {
            _stack = State(initialValue: TripDataStack(container: try TripModelContainer.app()))
        } catch {
            fatalError("BikeSpeed could not open its trip store: \(error)")
        }

        // Every trip detail view opened last session left a `.gpx` in `tmp/`, and iOS only reaps that
        // directory under storage pressure. Launch is the one moment no share sheet can still be reading
        // one, so it's the safe place to clear them.
        GPXExporter.clearExports()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationManager)
                .environment(addressLookupManager)
                .environment(settingsStore)
                .environment(tripManager)
                .environment(motionManager)
                .environment(stack)
                // What `@Query` in `TripLogListView` binds to. `TripDataStack` and the container have to be
                // the *same* store, or the list would read one and the saves would land in another.
                .modelContainer(stack.container)
                .environment(\.locale, settingsStore.appLanguage.locale ?? Locale.autoupdatingCurrent)
                .alert("Couldn't open your trip history", isPresented: $isShowingImportFailure) {
                    Button("OK") {}
                } message: {
                    // Deliberately specific: the rider is about to open the trip log and find it empty, and
                    // the one thing they need to know is that their rides are not gone.
                    Text("Your saved trips are still on this device, but couldn't be moved to the new format. They haven't been deleted. Updating the app again may fix it.")
                }
                .task {
                    // The one-shot JSON → SwiftData migration. A no-op on a fresh install and on every launch
                    // after the first successful one — it runs only while `TripLog.json` still exists, and a
                    // verified import is what deletes it. The trip log is behind a sheet that is closed at
                    // launch, and `@Query` picks the rows up live when the import lands, so nothing waits.
                    //
                    // `Task.detached` is not optional here. With `SWIFT_APPROACHABLE_CONCURRENCY = YES` a
                    // `nonisolated async` function runs on its *caller's* executor — the main actor, in a
                    // `.task` — which would put the log's decode and every route file's read-and-validate on
                    // the run loop at launch, for exactly as long as the rider's history is big. Same trap
                    // documented in `TripLogDetailView`.
                    let importer = LegacyTripLogImporter(
                        legacyDirectory: LegacyTripLogImporter.applicationSupportDirectory(),
                        repository: stack.repository
                    )
                    let result = await Task.detached { try await importer.run() }.result

                    // The importer refuses to delete a log it cannot parse, precisely so the rider's history
                    // survives a failure. Swallowing the error here would waste that: they would open the trip
                    // log, find it empty, and never learn that their rides are still sitting on disk.
                    if case .failure = result { isShowingImportFailure = true }
                }
        }
    }
}
