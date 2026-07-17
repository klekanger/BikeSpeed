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

    /// Held, but neither `@State` nor in the environment: not observable, no view reads it —
    /// `TripManager` is its only consumer and samples it directly. See `AltimeterManager`.
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

        // A store that won't open is fatal: every saved trip lives in it, and there is no honest degraded
        // mode — a throwaway in-memory store would silently accept rides and drop them at quit. The legacy
        // JSON is still on disk here, since `LegacyTripLogImporter` can't have run without a container to
        // import into and deletes nothing until the import verifies.
        do {
            _stack = State(initialValue: TripDataStack(container: try TripModelContainer.app()))
        } catch {
            fatalError("BikeSpeed could not open its trip store: \(error)")
        }

        // Trip detail views leave `.gpx` files in `tmp/`, which iOS only reaps under storage pressure.
        // Launch is the one moment no share sheet can still be reading one, so it's safe to clear them.
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
                // What `@Query` in `TripLogListView` binds to. Must be the *same* store as `TripDataStack`,
                // or the list would read one store and the saves would land in another.
                .modelContainer(stack.container)
                .environment(\.locale, settingsStore.appLanguage.locale ?? Locale.autoupdatingCurrent)
                .alert("Couldn't open your trip history", isPresented: $isShowingImportFailure) {
                    Button("OK") {}
                } message: {
                    // Deliberately specific: the rider will open the trip log and find it empty, and the one
                    // thing they need to know is that their rides are not gone.
                    Text("Your saved trips are still on this device, but couldn't be moved to the new format. They haven't been deleted. Updating the app again may fix it.")
                }
                .task {
                    // The one-shot JSON → SwiftData migration. A no-op after the first successful run — it
                    // runs only while `TripLog.json` exists, and a verified import deletes it. `@Query` picks
                    // the rows up live when the import lands, so nothing waits.
                    //
                    // `Task.detached` is load-bearing: with `SWIFT_APPROACHABLE_CONCURRENCY = YES` a
                    // `nonisolated async` function runs on its *caller's* executor — here the main actor, in a
                    // `.task` — putting the log decode and every route read-and-validate on the run loop at
                    // launch, for as long as the rider's history is big. Same trap as in `TripLogDetailView`.
                    let importer = LegacyTripLogImporter(
                        legacyDirectory: LegacyTripLogImporter.applicationSupportDirectory(),
                        repository: stack.repository
                    )
                    let result = await Task.detached { try await importer.run() }.result

                    // The importer refuses to delete a log it can't parse, so the rider's history survives a
                    // failure. Swallowing the error here would waste that — they'd find the log empty and
                    // never learn their rides are still on disk.
                    if case .failure = result { isShowingImportFailure = true }
                }
        }
    }
}
