import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var maxGaugeSpeedBinding: Binding<Double> {
        Binding(
            get: { settings.measurementSystem.maxGaugeSpeedValue(fromCanonicalKMH: settings.maxGaugeSpeedKMH) },
            set: { newValue in
                let measurementSystem = settings.measurementSystem
                let currentValue = measurementSystem.maxGaugeSpeedValue(fromCanonicalKMH: settings.maxGaugeSpeedKMH)
                let step = measurementSystem.maxGaugeSpeedStep
                // A unit switch can leave the current value off the step grid (e.g. converted from the
                // other unit). Rather than adding a full step to that odd value, snap in the pressed
                // direction to the nearest step multiple, so the displayed speed is always a round number.
                let quotient = currentValue / step
                let isOnStepGrid = abs(quotient.rounded() - quotient) < 0.001
                let steppedQuotient: Double
                if newValue > currentValue {
                    steppedQuotient = isOnStepGrid ? quotient.rounded() + 1 : quotient.rounded(.up)
                } else {
                    steppedQuotient = isOnStepGrid ? quotient.rounded() - 1 : quotient.rounded(.down)
                }
                let range = measurementSystem.maxGaugeSpeedRange
                let roundedValue = min(max(steppedQuotient * step, range.lowerBound), range.upperBound)
                settings.maxGaugeSpeedKMH = measurementSystem.canonicalKMH(fromMaxGaugeSpeedValue: roundedValue)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gauge") {
                    Stepper(
                        value: maxGaugeSpeedBinding,
                        in: settings.measurementSystem.maxGaugeSpeedRange,
                        step: settings.measurementSystem.maxGaugeSpeedStep
                    ) {
                        HStack {
                            Text("Max speed")
                            Spacer()
                            Text(settings.measurementSystem.formattedMaxGaugeSpeed(fromCanonicalKMH: settings.maxGaugeSpeedKMH))
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

                Section("Language") {
                    Picker("Language", selection: $settings.appLanguage) {
                        Text("System").tag(AppLanguage.system)
                        Text(verbatim: "Norsk").tag(AppLanguage.norwegian)
                        Text(verbatim: "English").tag(AppLanguage.english)
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
