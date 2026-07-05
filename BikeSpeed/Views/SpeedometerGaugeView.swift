import SwiftUI

/// Composes the static gauge face with the rotating needle and center unit/icon label.
struct SpeedometerGaugeView: View {
    let speed: Double // m/s
    let maxGaugeSpeedKMH: Double
    let measurementSystem: MeasurementSystem

    private var maxSpeedInDisplayUnit: Double {
        measurementSystem.maxGaugeSpeedValue(fromCanonicalKMH: maxGaugeSpeedKMH)
    }

    private var speedInDisplayUnit: Double {
        measurementSystem.speedValue(metersPerSecond: speed)
    }

    private var needleAngle: Angle {
        let fraction = max(0, min(speedInDisplayUnit / maxSpeedInDisplayUnit, 1))
        return .degrees(-135 + 270 * fraction)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)

            ZStack {
                GaugeFaceView(maxSpeed: maxSpeedInDisplayUnit)

                NeedleView()
                    .frame(width: side, height: side)
                    .rotationEffect(needleAngle)
                    .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: needleAngle)

                Circle()
                    .fill(Color(white: 0.15))
                    .overlay(Circle().stroke(Color(white: 0.35), lineWidth: side * 0.01))
                    .frame(width: side * 0.12, height: side * 0.12)

                VStack(spacing: side * 0.01) {
                    Text(measurementSystem.gaugeUnitLabel)
                        .font(.system(size: side * 0.05, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "bicycle")
                        .font(.system(size: side * 0.06))
                        .foregroundStyle(.secondary)
                }
                .offset(y: side * 0.22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    ZStack {
        Color.black
        SpeedometerGaugeView(speed: 10, maxGaugeSpeedKMH: 60, measurementSystem: .metric)
            .padding(24)
    }
    .ignoresSafeArea()
}
