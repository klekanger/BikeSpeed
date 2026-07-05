import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private let maxSpeedStep: Double = 5
    private let maxSpeedRange: ClosedRange<Double> = 20...200

    var body: some View {
        NavigationStack {
            Form {
                Section("Gauge") {
                    Stepper(value: $settings.maxGaugeSpeedKMH, in: maxSpeedRange, step: maxSpeedStep) {
                        HStack {
                            Text("Max speed")
                            Spacer()
                            Text(settings.measurementSystem.formattedSpeed(metersPerSecond: settings.maxGaugeSpeedKMH / 3.6, fractionDigits: 0))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Units") {
                    Picker("Units", selection: $settings.measurementSystem) {
                        Text("Metric").tag(MeasurementSystem.metric)
                        Text("Imperial").tag(MeasurementSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView(settings: SettingsStore())
}
