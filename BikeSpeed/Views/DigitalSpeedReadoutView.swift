import SwiftUI

struct DigitalSpeedReadoutView: View {
    let speed: Double // m/s
    let measurementSystem: MeasurementSystem

    private var displayValue: Double {
        measurementSystem.speedValue(metersPerSecond: speed)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(displayValue, format: .number.precision(.fractionLength(0)))
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text(measurementSystem.gaugeUnitLabel.lowercased())
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    ZStack {
        Color.black
        DigitalSpeedReadoutView(speed: 10.1, measurementSystem: .metric)
    }
    .ignoresSafeArea()
}
