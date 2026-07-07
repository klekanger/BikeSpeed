import SwiftUI
import CoreLocation

/// The 2×2 stats grid shown under the gauge, wrapped in the same brushed-metal bezel as the
/// speedometer. Cells, clockwise from top-left: average speed, direction of travel, distance,
/// altitude. Tapping the average-speed cell swaps it for the trip's max speed; tapping the
/// altitude cell swaps it for the GPS position.
struct StatsPanel: View {
    let averageSpeed: Double // m/s
    let maxSpeed: Double // m/s
    let distance: Double // meters
    let altitude: Double? // meters
    let coordinate: CLLocationCoordinate2D?
    let course: Double? // degrees, nil until a reliable course exists
    let measurementSystem: MeasurementSystem

    @Environment(\.locale) private var locale
    @EnvironmentObject private var motionManager: MotionManager

    @State private var showingMaxSpeed = false
    @State private var showingPosition = false

    private let cornerRadius: CGFloat = 24
    private let bezelWidth: CGFloat = 5
    private let dividerColor = Color.white.opacity(0.12)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                speedCell
                verticalDivider
                directionCell
            }
            horizontalDivider
            HStack(spacing: 0) {
                distanceCell
                verticalDivider
                altitudeCell
            }
        }
        .background(Color.gaugeFaceCenter, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    AngularGradient(gradient: .metallicBezel, center: .center, angle: .radians(motionManager.tilt.width * 1.1)),
                    lineWidth: bezelWidth
                )
        )
    }

    private var speedCell: StatCell {
        StatCell(
            systemImage: showingMaxSpeed ? "gauge.with.dots.needle.100percent" : "speedometer",
            value: measurementSystem.formattedSpeed(metersPerSecond: showingMaxSpeed ? maxSpeed : averageSpeed, locale: locale),
            caption: showingMaxSpeed ? "Max speed" : "Average speed",
            onTap: { showingMaxSpeed.toggle() }
        )
    }

    private var directionCell: StatCell {
        StatCell(
            systemImage: "location.north.fill",
            value: course.map { CompassDirection(course: $0).abbreviation } ?? "--",
            caption: "Direction of travel",
            iconRotation: .degrees(course ?? 0),
            iconTint: course == nil ? .secondary : .orange
        )
    }

    private var distanceCell: StatCell {
        StatCell(
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            value: measurementSystem.formattedDistance(meters: distance, locale: locale),
            caption: "Distance"
        )
    }

    private var altitudeCell: StatCell {
        StatCell(
            systemImage: showingPosition ? "location" : "mountain.2",
            value: showingPosition ? formattedPosition : (altitude.map { measurementSystem.formattedAltitude(meters: $0, locale: locale) } ?? "--"),
            caption: showingPosition ? "Position" : "Altitude",
            onTap: { showingPosition.toggle() }
        )
    }

    private var verticalDivider: some View {
        Rectangle().fill(dividerColor).frame(width: 1)
    }

    private var horizontalDivider: some View {
        Rectangle().fill(dividerColor).frame(height: 1)
    }

    private var formattedPosition: String {
        guard let coordinate else { return "--" }
        let latHemisphere = coordinate.latitude >= 0 ? "N" : "S"
        let lonHemisphere = coordinate.longitude >= 0 ? "E" : "W"
        let lat = String(format: "%.5f°", abs(coordinate.latitude))
        let lon = String(format: "%.5f°", abs(coordinate.longitude))
        return "\(lat) \(latHemisphere)\n\(lon) \(lonHemisphere)"
    }
}

#Preview {
    ZStack {
        Color.black
        StatsPanel(
            averageSpeed: 6.86,
            maxSpeed: 11.4,
            distance: 28_560,
            altitude: 145,
            coordinate: CLLocationCoordinate2D(latitude: 59.913868, longitude: 10.752245),
            course: 45,
            measurementSystem: .metric
        )
        .frame(height: 260)
        .padding()
        .environmentObject(MotionManager())
    }
    .ignoresSafeArea()
}
