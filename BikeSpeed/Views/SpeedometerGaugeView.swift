import SwiftUI

/// Composes the static gauge face with the rotating needle and center unit/icon label.
struct SpeedometerGaugeView: View {
    let speed: Double // m/s
    let maxGaugeSpeedKMH: Double
    let measurementSystem: MeasurementSystem

    @Environment(\.locale) private var locale
    @Environment(MotionManager.self) private var motionManager

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
                GaugeFaceView(maxSpeed: maxSpeedInDisplayUnit, tilt: motionManager.tilt)

                NeedleView()
                    .frame(width: side, height: side)
                    .rotationEffect(needleAngle)
                    .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: needleAngle)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.8), Color(white: 0.4), Color(white: 0.12)],
                            center: UnitPoint(
                                x: 0.35 + motionManager.tilt.width * 0.28,
                                y: 0.32 + motionManager.tilt.height * 0.28
                            ),
                            startRadius: 0,
                            endRadius: side * 0.07
                        )
                    )
                    .overlay(Circle().stroke(Color(white: 0.55), lineWidth: side * 0.004))
                    .shadow(color: .black.opacity(0.5), radius: side * 0.008, x: 0, y: side * 0.004)
                    .frame(width: side * 0.12, height: side * 0.12)

                VStack(spacing: side * 0.015) {
                    Text(measurementSystem.gaugeUnitLabel(locale: locale))
                        .font(.system(size: side * 0.05, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)

                    Text(speedInDisplayUnit, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: side * 0.08, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: speedInDisplayUnit))
                        .animation(.default, value: speedInDisplayUnit)
                        .frame(width: side * 0.22) // fixed width leaving room for 3 digits
                        .padding(.vertical, side * 0.012)
                        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: side * 0.03))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Current speed")
                        .accessibilityValue(measurementSystem.formattedSpeed(metersPerSecond: speed, locale: locale))
                }
                .offset(y: side * 0.23)
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
            .environment(MotionManager())
    }
    .ignoresSafeArea()
}
