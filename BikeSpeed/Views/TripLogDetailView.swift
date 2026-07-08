import Charts
import SwiftUI

/// Full detail for a single saved trip: date, duration, distance, average/max speed, and a
/// height-profile chart plotted against accumulated distance.
struct TripLogDetailView: View {
    let entry: TripLogEntry

    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                LabeledContent("Date", value: entry.startDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: TripDurationFormatting.formatted(seconds: entry.duration, locale: locale))
                LabeledContent("Distance", value: settingsStore.measurementSystem.formattedDistance(meters: entry.distance, locale: locale))
                LabeledContent("Average speed", value: settingsStore.measurementSystem.formattedSpeed(metersPerSecond: entry.averageSpeed, locale: locale))
                LabeledContent("Max speed", value: settingsStore.measurementSystem.formattedSpeed(metersPerSecond: entry.maxSpeed, locale: locale))
            }

            Section("Height profile") {
                if entry.altitudeProfile.isEmpty {
                    Text("No altitude data for this trip")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(entry.altitudeProfile, id: \.distance) { sample in
                        AreaMark(
                            x: .value("Distance", sample.distance),
                            y: .value("Altitude", sample.altitude)
                        )
                        .foregroundStyle(.orange.opacity(0.3))
                        LineMark(
                            x: .value("Distance", sample.distance),
                            y: .value("Altitude", sample.altitude)
                        )
                        .foregroundStyle(.orange)
                    }
                    .frame(height: 200)
                }
            }
        }
        .navigationTitle(entry.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TripLogDetailView(entry: TripLogEntry(
            id: UUID(),
            startDate: Date(),
            duration: 1830,
            distance: 12_400,
            averageSpeed: 6.8,
            maxSpeed: 11.4,
            altitudeProfile: stride(from: 0.0, through: 12_400.0, by: 200.0).map {
                AltitudeSample(distance: $0, altitude: 100 + 30 * sin($0 / 1000))
            }
        ))
        .environmentObject(SettingsStore())
    }
}
