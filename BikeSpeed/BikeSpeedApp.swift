//
//  BikeSpeedApp.swift
//  BikeSpeed
//
//  Created by Kurt Lekanger on 04/07/2026.
//

import SwiftUI

@main
struct BikeSpeedApp: App {
    @StateObject private var locationManager: LocationManager
    @StateObject private var addressLookupManager: AddressLookupManager
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var tripManager: TripManager
    @StateObject private var motionManager = MotionManager()
    @StateObject private var tripLogStore = TripLogStore()

    init() {
        let locationManager = LocationManager()
        let settingsStore = SettingsStore()
        _locationManager = StateObject(wrappedValue: locationManager)
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _tripManager = StateObject(wrappedValue: TripManager(locationManager: locationManager, settings: settingsStore))
        _addressLookupManager = StateObject(wrappedValue: AddressLookupManager(locationManager: locationManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(addressLookupManager)
                .environmentObject(settingsStore)
                .environmentObject(tripManager)
                .environmentObject(motionManager)
                .environmentObject(tripLogStore)
                .environment(\.locale, settingsStore.appLanguage.locale ?? Locale.autoupdatingCurrent)
        }
    }
}
