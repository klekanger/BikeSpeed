//
//  ContentView.swift
//  BikeSpeed
//
//  Created by Kurt Lekanger on 04/07/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var tripManager: TripManager

    @State private var isShowingSettings = false

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
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(SettingsStore())
        .environmentObject(TripManager(locationManager: LocationManager()))
        .environmentObject(MotionManager())
}
