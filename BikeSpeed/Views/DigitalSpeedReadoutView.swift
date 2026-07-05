import SwiftUI

struct DigitalSpeedReadoutView: View {
    let speed: Double // m/s
    let measurementSystem: MeasurementSystem

    @Environment(\.locale) private var locale

    private var displayValue: Double {
        measurementSystem.speedValue(metersPerSecond: speed)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(displayValue, format: .number.precision(.fractionLength(0)))
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text(measurementSystem.gaugeUnitLabel(locale: locale).lowercased())
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current speed")
        .accessibilityValue(measurementSystem.formattedSpeed(metersPerSecond: speed, locale: locale))
    }
}

#Preview {
    ZStack {
        Color.black
        DigitalSpeedReadoutView(speed: 10.1, measurementSystem: .metric)
    }
    .ignoresSafeArea()
}
