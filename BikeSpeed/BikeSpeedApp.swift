//
//  BikeSpeedApp.swift
//  BikeSpeed
//
//  Created by Kurt Lekanger on 04/07/2026.
//

import SwiftUI

@main
struct BikeSpeedApp: App {
    @State private var locationManager: LocationManager
    @State private var addressLookupManager: AddressLookupManager
    @State private var settingsStore: SettingsStore
    @State private var tripManager: TripManager
    @State private var motionManager = MotionManager()
    @State private var tripLogStore = TripLogStore()

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
                .environment(tripLogStore)
                .environment(\.locale, settingsStore.appLanguage.locale ?? Locale.autoupdatingCurrent)
        }
    }
}
