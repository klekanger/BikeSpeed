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
                    averageSpeed: tripManager.averageSpeed,
                    maxSpeed: tripManager.maxSpeed,
                    distance: tripManager.accumulatedDistance,
                    altitude: locationManager.altitude,
                    coordinate: locationManager.coordinate,
                    course: locationManager.course,
                    streetName: addressLookupManager.streetName,
                    measurementSystem: settingsStore.measurementSystem
                )
                .frame(height: 260)
                .padding(.horizontal)

                Spacer()

                TripControlBar(tripManager: tripManager)
                    .padding(.bottom, 12)
            }

            VStack {
                HStack {
                    GPSSignalIndicatorView(quality: locationManager.signalQuality, isTracking: tripManager.state == .running)
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

    ContentView()
        .environmentObject(locationManager)
        .environmentObject(AddressLookupManager(locationManager: locationManager))
        .environmentObject(SettingsStore())
        .environmentObject(TripManager(locationManager: locationManager))
        .environmentObject(MotionManager())
        .environmentObject(TripLogStore())
}
