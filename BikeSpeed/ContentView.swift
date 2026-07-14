//
//  ContentView.swift
//  BikeSpeed
//
//  Created by Kurt Lekanger on 04/07/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var addressLookupManager: AddressLookupManager
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var tripManager: TripManager
    @EnvironmentObject private var tripLogStore: TripLogStore

    @State private var isShowingSettings = false
    @State private var isShowingTripLog = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                Spacer(minLength: 4)

                SpeedometerGaugeView(
                    speed: locationManager.displaySpeed,
                    maxGaugeSpeedKMH: settingsStore.maxGaugeSpeedKMH,
                    measurementSystem: settingsStore.measurementSystem
                )
                .frame(maxWidth: .infinity)

                StatsPanel(
                    trip: TripStats(
                        averageSpeed: tripManager.averageSpeed,
                        maxSpeed: tripManager.maxSpeed,
                        distance: tripManager.accumulatedDistance,
                        duration: tripManager.elapsedActiveDuration,
                        totalAscent: tripManager.totalAscent,
                        grade: tripManager.currentGrade,
                        isAutoPaused: tripManager.isAutoPaused
                    ),
                    location: LocationReadout(
                        altitude: locationManager.altitude,
                        coordinate: locationManager.coordinate,
                        // Not `course`: that one goes stale the moment the rider stops, and the arrow with
                        // it. `travelDirection` hands over to the compass at a standstill — see `LocationManager`.
                        course: locationManager.travelDirection,
                        streetName: addressLookupManager.streetName
                    ),
                    measurementSystem: settingsStore.measurementSystem,
                    appLanguage: settingsStore.appLanguage
                )
                .frame(height: 260)
                .padding(.horizontal)

                Spacer()

                TripControlBar(tripManager: tripManager)
                    .padding(.bottom, 12)
            }

            VStack {
                HStack {
                    GPSSignalIndicatorView(
                        quality: locationManager.signalQuality,
                        isTracking: tripManager.state == .running && !tripManager.isAutoPaused
                    )
                        .font(.system(size: 20))
                        .padding(12)

                    Spacer()

                    Button("Trip Log", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                        isShowingTripLog = true
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .buttonStyle(.plain)

                    Button("Settings", systemImage: "gearshape.fill") {
                        isShowingSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            locationManager.requestAuthorization()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settingsStore)
        }
        .sheet(isPresented: $isShowingTripLog) {
            TripLogListView(store: tripLogStore)
        }
    }
}

#Preview {
    let locationManager = LocationManager()
    let settingsStore = SettingsStore()

    ContentView()
        .environmentObject(locationManager)
        .environmentObject(AddressLookupManager(locationManager: locationManager))
        .environmentObject(settingsStore)
        .environmentObject(TripManager(locationManager: locationManager, altimeter: AltimeterManager(), settings: settingsStore))
        .environmentObject(MotionManager())
        .environmentObject(TripLogStore())
}
