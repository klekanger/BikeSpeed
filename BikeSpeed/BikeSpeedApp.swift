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
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var tripManager: TripManager

    init() {
        let locationManager = LocationManager()
        _locationManager = StateObject(wrappedValue: locationManager)
        _tripManager = StateObject(wrappedValue: TripManager(locationManager: locationManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(settingsStore)
                .environmentObject(tripManager)
                .environment(\.locale, settingsStore.appLanguage.locale ?? Locale.autoupdatingCurrent)
        }
    }
}
