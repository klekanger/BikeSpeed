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

                HStack {
                    DigitalSpeedReadoutView(
                        speed: locationManager.displaySpeed,
                        measurementSystem: settingsStore.measurementSystem
                    )
                    Spacer()
                    DirectionIndicatorView(course: locationManager.course)
                }
                .padding(.horizontal)

                StatsPanel(
                    averageSpeed: tripManager.averageSpeed,
                    distance: tripManager.accumulatedDistance,
                    altitude: locationManager.altitude,
                    coordinate: locationManager.coordinate,
                    measurementSystem: settingsStore.measurementSystem
                )
                .padding(.horizontal)

                Spacer()

                TripControlBar(tripManager: tripManager)
                    .padding(.bottom, 12)
            }

            VStack {
                HStack {
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
