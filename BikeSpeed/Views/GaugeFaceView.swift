import SwiftUI

/// Draws the static dial: background, tick marks, numeric labels, and the danger-zone arc.
/// Deliberately separate from the needle so the (comparatively expensive) Canvas redraw only
/// happens when `maxSpeed` changes or `tilt` drifts, not on every GPS update. `tilt` is a small,
/// heavily-smoothed accelerometer vector (see `MotionManager`) that nudges the metallic gradients
/// so the bezel/face look like they catch light as the phone moves — it is already throttled and
/// low-pass filtered upstream, so redrawing on every change stays cheap.
struct GaugeFaceView: View {
    let maxSpeed: Double
    var tilt: CGSize = .zero

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private let startAngle: Double = -135
    private let sweepAngle: Double = 270
    private let minorPerMajor = 5
    private let dangerStartFraction = 0.85
    /// Candidate spacings for major ticks, ascending — always a "nice" round number so labels
    /// read as multiples of 5, 10, 25, etc. rather than of whatever `maxSpeed` happens to be.
    private let majorStepCandidates: [Double] = [5, 10, 15, 20, 25, 50, 100]
    /// Upper bound on the number of major ticks, so the scale doesn't get too fine-grained
    /// for large `maxSpeed` values.
    private let maxMajorDivisions = 10.0

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * 0.92

            drawFace(context: context, center: center, radius: radius)
            drawDangerArc(context: context, center: center, radius: radius)
            drawTicksAndLabels(context: context, center: center, radius: radius)
        }
    }

    private func gaugeAngle(fraction: Double) -> Angle {
        .degrees(startAngle + sweepAngle * fraction)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(sin(angle.radians)),
            y: center.y - radius * CGFloat(cos(angle.radians))
        )
    }

    private func drawFace(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let lightCenter = CGPoint(x: center.x + tilt.width * radius * 0.35, y: center.y + tilt.height * radius * 0.35)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(Gradient(colors: [Color(white: 0.15), .gaugeFaceCenter]), center: lightCenter, startRadius: 0, endRadius: radius)
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .conicGradient(
                Gradient(colors: [
                    Color(white: 0.8), Color(white: 0.25), Color(white: 0.9),
                    Color(white: 0.2), Color(white: 0.65), Color(white: 0.3),
                    Color(white: 0.8),
                ]),
                center: center,
                angle: .radians(tilt.width * 1.1)
            ),
            lineWidth: radius * 0.05
        )
    }

    private func drawDangerArc(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let arcRadius = radius * 0.92
        let steps = 24
        var path = Path()
        for i in 0...steps {
            let fraction = dangerStartFraction + (1 - dangerStartFraction) * Double(i) / Double(steps)
            let p = point(center: center, radius: arcRadius, angle: gaugeAngle(fraction: fraction))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        let lineWidth = differentiateWithoutColor ? radius * 0.08 : radius * 0.05
        context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    /// Picks the finest step (from `majorStepCandidates`) that still keeps the major tick
    /// count at or below `maxMajorDivisions`. The step need not evenly divide `maxSpeed` —
    /// ticks are placed by their actual fraction of the scale, so the last one or two minor
    /// ticks before the top of the dial may simply be omitted, same as on a real gauge.
    private func majorStep(for maxSpeed: Double) -> Double {
        let minStep = maxSpeed / maxMajorDivisions
        return majorStepCandidates.first(where: { $0 >= minStep }) ?? majorStepCandidates.last!
    }

    private func drawTicksAndLabels(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let step = majorStep(for: maxSpeed)
        let minorStep = step / Double(minorPerMajor)
        let totalMinorTicks = Int((maxSpeed / minorStep).rounded(.down))

        for i in 0...totalMinorTicks {
            let value = Double(i) * minorStep
            let fraction = value / maxSpeed
            let isMajor = i % minorPerMajor == 0
            let outer = radius * 0.88
            let inner = isMajor ? radius * 0.76 : radius * 0.82
            let angle = gaugeAngle(fraction: fraction)
            let p1 = point(center: center, radius: outer, angle: angle)
            let p2 = point(center: center, radius: inner, angle: angle)

            var tickPath = Path()
            tickPath.move(to: p1)
            tickPath.addLine(to: p2)

            let isDanger = fraction >= dangerStartFraction
            let color: Color = isDanger ? .orange : (isMajor ? .white : Color(white: 0.6))
            let baseWidth = isMajor ? radius * 0.02 : radius * 0.01
            let tickWidth = isDanger && differentiateWithoutColor ? baseWidth * 1.8 : baseWidth
            context.stroke(tickPath, with: .color(color), lineWidth: tickWidth)

            if isMajor {
                let labelPoint = point(center: center, radius: radius * 0.64, angle: angle)
                context.draw(
                    Text(formattedTickLabel(value))
                        .font(.system(size: radius * 0.16, weight: .semibold))
                        .foregroundColor(.white),
                    at: labelPoint
                )
            }
        }
    }

    private func formattedTickLabel(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    ZStack {
        Color.black
        GaugeFaceView(maxSpeed: 60)
            .padding(40)
    }
    .ignoresSafeArea()
}
