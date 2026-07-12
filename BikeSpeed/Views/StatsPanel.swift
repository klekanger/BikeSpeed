import SwiftUI
import CoreLocation

/// What the trip has accumulated so far. A value rather than five loose arguments: `distance` and
/// `duration` are both `Double` underneath, so nothing but the argument label tells them apart, and
/// the panel's parameter list only grows as stats are added.
struct TripStats {
    let averageSpeed: Double // m/s
    let maxSpeed: Double // m/s
    let distance: Double // meters
    let duration: TimeInterval // seconds of active (moving) time; auto-paused time is excluded
    let isAutoPaused: Bool
}

/// Where the rider is right now, independent of any trip. Each `nil` means that value hasn't
/// resolved yet rather than that it's zero.
struct LocationReadout {
    let altitude: Double? // meters
    let coordinate: CLLocationCoordinate2D?
    let course: Double? // degrees
    let streetName: String? // nil until reverse geocoding resolves one
}

/// The 2×2 stats grid shown under the gauge, wrapped in the same brushed-metal bezel as the
/// speedometer. Cells, clockwise from top-left: average speed, direction of travel, distance,
/// altitude. Tapping the average-speed cell swaps it for the trip's max speed; tapping the
/// distance cell swaps it for the trip's duration; tapping the altitude cell swaps it for the GPS
/// position.
struct StatsPanel: View {
    let trip: TripStats
    let location: LocationReadout
    let measurementSystem: MeasurementSystem
    let appLanguage: AppLanguage

    @Environment(\.locale) private var locale
    @EnvironmentObject private var motionManager: MotionManager

    @State private var showingMaxSpeed = false
    @State private var showingDuration = false
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
            value: measurementSystem.formattedSpeed(metersPerSecond: showingMaxSpeed ? trip.maxSpeed : trip.averageSpeed, locale: locale),
            caption: showingMaxSpeed ? "Max speed" : "Average speed",
            onTap: { showingMaxSpeed.toggle() }
        )
    }

    /// The street name takes over the caption line; until one resolves the line stays blank rather
    /// than falling back to a label — the arrow and compass letter carry the cell alone.
    private var directionCell: StatCell {
        StatCell(
            systemImage: "location.north.fill",
            value: location.course.map { CompassDirection(course: $0).abbreviation(language: appLanguage) } ?? "--",
            caption: "Direction of travel",
            captionContent: .data(location.streetName),
            iconRotation: .degrees(location.course ?? 0),
            iconTint: location.course == nil ? .secondary : .orange
        )
    }

    /// Distance and duration are the two stats an auto-pause freezes, so the "Auto-paused" caption
    /// lands here and explains both — whichever of the two the cell happens to be showing.
    private var distanceCell: StatCell {
        StatCell(
            systemImage: showingDuration ? "stopwatch" : "point.topleft.down.curvedto.point.bottomright.up",
            value: showingDuration
                ? TripDurationFormatting.formatted(seconds: trip.duration, locale: locale)
                : measurementSystem.formattedDistance(meters: trip.distance, locale: locale),
            caption: showingDuration ? "Duration" : "Distance",
            captionContent: trip.isAutoPaused ? .text("Auto-paused") : .name,
            iconTint: trip.isAutoPaused ? .secondary : .orange,
            onTap: { showingDuration.toggle() }
        )
    }

    private var altitudeCell: StatCell {
        StatCell(
            systemImage: showingPosition ? "location" : "mountain.2",
            value: showingPosition ? formattedPosition : (location.altitude.map { measurementSystem.formattedAltitude(meters: $0, locale: locale) } ?? "--"),
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

    /// Hemisphere letters share the compass abbreviations' catalog keys, so they follow the same
    /// east/west swap in Norwegian (Ø/V) that the direction cell does.
    private var formattedPosition: String {
        guard let coordinate = location.coordinate else { return "--" }
        let latHemisphere = appLanguage.localizedString(forKey: coordinate.latitude >= 0 ? "N" : "S")
        let lonHemisphere = appLanguage.localizedString(forKey: coordinate.longitude >= 0 ? "E" : "W")
        let lat = String(format: "%.5f°", abs(coordinate.latitude))
        let lon = String(format: "%.5f°", abs(coordinate.longitude))
        return "\(lat) \(latHemisphere)\n\(lon) \(lonHemisphere)"
    }
}

#Preview {
    ZStack {
        Color.black
        StatsPanel(
            trip: TripStats(
                averageSpeed: 6.86,
                maxSpeed: 11.4,
                distance: 28_560,
                duration: 4_324,
                isAutoPaused: false
            ),
            location: LocationReadout(
                altitude: 145,
                coordinate: CLLocationCoordinate2D(latitude: 59.913868, longitude: 10.752245),
                course: 45,
                streetName: "Karl Johans gate"
            ),
            measurementSystem: .metric,
            appLanguage: .system
        )
        .frame(height: 260)
        .padding()
        .environmentObject(MotionManager())
    }
    .ignoresSafeArea()
}
