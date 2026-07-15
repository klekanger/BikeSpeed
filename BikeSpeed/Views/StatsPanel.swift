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
    let totalAscent: Double? // meters; nil until any usable altitude has arrived — not the same as 0
    let grade: Double? // rise/run, e.g. 0.05 for 5 %; nil until the trip has ridden a window's worth
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
/// altitude. All but the direction cell hold a second readout — max speed, duration, GPS position —
/// that a tap or a horizontal swipe pages to, and their page indicators are what say so.
struct StatsPanel: View {
    let trip: TripStats
    let location: LocationReadout
    let measurementSystem: MeasurementSystem
    let appLanguage: AppLanguage

    @Environment(\.locale) private var locale
    @Environment(MotionManager.self) private var motionManager

    @State private var speedPage = 0
    @State private var distancePage = 0
    @State private var altitudePage = 0

    private var showingMaxSpeed: Bool { speedPage == 1 }
    private var showingDuration: Bool { distancePage == 1 }
    private var showingClimb: Bool { altitudePage == 1 }
    private var showingPosition: Bool { altitudePage == 2 }

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
            paging: .init(page: $speedPage, names: ["Average speed", "Max speed"])
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
            captionContent: trip.isAutoPaused ? .text("Auto-paused") : .name,
            iconTint: trip.isAutoPaused ? .secondary : .orange,
            paging: .init(page: $distancePage, names: ["Distance", "Duration"]),
            pageIndicatorInset: bottomRowIndicatorInset
        )
    }

    /// The altitude page's caption line carries the live gradient the way the direction cell's
    /// carries the street: data in place of the name. Unlike the street, the gradient is nil more
    /// often than not (standstill, window not yet ridden full), and a bare number over a blank line
    /// doesn't say what it is — so nil falls back to the page's name rather than to a blank.
    private var altitudeCell: StatCell {
        StatCell(
            systemImage: showingPosition ? "location" : (showingClimb ? "arrow.up.right" : "mountain.2"),
            value: altitudeCellValue,
            captionContent: altitudeCaption,
            paging: .init(page: $altitudePage, names: ["Altitude", "Climb", "Position"]),
            pageIndicatorInset: bottomRowIndicatorInset
        )
    }

    private var altitudeCaption: StatCell.Caption {
        guard showingClimb == false, showingPosition == false, let formattedGrade else { return .name }
        return .data(formattedGrade)
    }

    private var altitudeCellValue: String {
        if showingPosition { return formattedPosition }
        if showingClimb {
            // "--" like the altitude readout below, not "0 m": a trip with no altitude data hasn't
            // measured a flat ride, it hasn't measured anything.
            return trip.totalAscent.map { measurementSystem.formattedAltitude(meters: $0, locale: locale) } ?? "--"
        }
        return location.altitude.map { measurementSystem.formattedAltitude(meters: $0, locale: locale) } ?? "--"
    }

    /// "▲ 4 %" climbing, "▼ 4 %" descending, a bare "0 %" on the flat. Rounded to whole percent — a
    /// live gradient's decimals are noise to a rider — and rounded *before* the arrow is chosen: the
    /// raw sign flaps around zero on flat ground, and pairing it with a rounded magnitude would show
    /// the self-contradictory "▼ 0 %".
    private var formattedGrade: String? {
        guard let grade = trip.grade else { return nil }
        let wholePercent = (abs(grade) * 100).rounded()
        let magnitude = (wholePercent / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
        guard wholePercent > 0 else { return magnitude }
        let arrow = grade < 0 ? "▼" : "▲"
        return "\(arrow) \(magnitude)"
    }

    /// The bezel is stroked over the panel's outer edge, so it eats into the bottom row's cells in a
    /// way the hairline divider above them doesn't. Without this the bottom dots would read as
    /// crowded against the bezel while the top row's sat comfortably above the divider.
    private var bottomRowIndicatorInset: CGFloat {
        StatCell.defaultPageIndicatorInset + bezelWidth
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
                totalAscent: 312,
                grade: 0.042,
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
        .environment(MotionManager())
    }
    .ignoresSafeArea()
}
