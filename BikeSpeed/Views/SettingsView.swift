import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

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
                Section {
                    Toggle("Auto-pause", isOn: $settings.autoPauseEnabled)
                } header: {
                    Text("Trip")
                } footer: {
                    Text("Pauses distance and time automatically when you stop.")
                }

                Section("Gauge") {
                    Stepper(
                        value: maxGaugeSpeedBinding,
                        in: settings.measurementSystem.maxGaugeSpeedRange,
                        step: settings.measurementSystem.maxGaugeSpeedStep
                    ) {
                        HStack {
                            Text("Max speed")
                            Spacer()
                            Text(settings.measurementSystem.formattedMaxGaugeSpeed(fromCanonicalKMH: settings.maxGaugeSpeedKMH, locale: locale))
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
                
                // Only after an actual denial on barometer hardware — the prompt itself can never
                // be re-shown, so the Settings toggle is the one way back (see the predicate's doc).
                if AltimeterManager.needsMotionPermissionHint() {
                    Section {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    } header: {
                        Text("Climb")
                    } footer: {
                        Text("Motion & Fitness is off, so climb is measured by GPS. Turn it on for more accurate climb readings.")
                            .foregroundStyle(Color.red)
                    }
                }

                // Scrolls with the content rather than sitting in a safe-area inset, so it can
                // never overlap the last section however many sections are shown above it.
                Section {
                } footer: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(verbatim: "BikeSpeed")
                            Text(verbatim: "v\(appVersion)")
                        }
                        .foregroundStyle(.primary)
                        Text(verbatim: "Lekanger tekst og kode 2026")
                        Text(verbatim: "MIT License")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
           .navigationTitle(settings.appLanguage.localizedString(forKey: "Settings"))
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
