import SwiftUI
import CoreLocation

/// What the trip has accumulated so far. A value, not loose arguments: `distance` and `duration` are
/// both `Double`, so nothing but the label tells them apart, and the panel's parameter list would
/// only grow as stats are added.
struct TripStats {
    let state: TripState
    let averageSpeed: Double // m/s
    let maxSpeed: Double // m/s
    let distance: Double // meters
    let duration: TimeInterval // seconds of active (moving) time; auto-paused time is excluded
    let totalAscent: Double? // meters; nil until any usable altitude has arrived — not the same as 0
    let totalDescent: Double? // meters, positive; nil on the same terms as `totalAscent`
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

/// The altitude cell's readouts, in page order. Climb and descent are *trip* stats, so they only
/// appear once a trip has started: before that they have nothing to report and would sit at "--" for
/// the whole ride-up, two dead pages between the two live ones. They stay for a paused trip — a rider
/// stopped at the top of a hill hasn't stopped caring how much they climbed, and it's the number to
/// look at before saving.
enum AltitudeCellPage: CaseIterable {
    case altitude
    case climb
    case descent
    case position

    static func pages(tripState: TripState) -> [AltitudeCellPage] {
        tripState == .idle ? [.altitude, .position] : allCases
    }

    var name: LocalizedStringKey {
        switch self {
        case .altitude: "Altitude"
        case .climb: "Climb"
        case .descent: "Descent"
        case .position: "Position"
        }
    }

    var systemImage: String {
        switch self {
        case .altitude: "mountain.2"
        case .climb: "arrow.up.right"
        case .descent: "arrow.down.right"
        case .position: "location"
        }
    }
}

/// The 2×2 stats grid under the gauge, in the same brushed-metal bezel as the speedometer. Cells,
/// clockwise from top-left: average speed, direction of travel, distance, altitude. All but the
/// direction cell hold further readouts (max speed, duration, climb, descent, GPS position) reached
/// by tap or swipe — see `AltitudeCellPage` for the one cell whose page set isn't fixed.
struct StatsPanel: View {
    let trip: TripStats
    let location: LocationReadout
    let measurementSystem: MeasurementSystem
    let appLanguage: AppLanguage

    @Environment(\.locale) private var locale
    @Environment(MotionManager.self) private var motionManager

    @State private var speedPage = 0
    @State private var distancePage = 0
    /// The altitude cell alone is held as the readout rather than as an index, because its page set
    /// changes with the trip state — an index would point at a different readout after a Start, and
    /// off the end of the array after a Reset.
    @State private var altitudePage: AltitudeCellPage = .altitude

    private var showingMaxSpeed: Bool { speedPage == 1 }
    private var showingDuration: Bool { distancePage == 1 }

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

    /// The street name takes over the caption line; until one resolves the line stays blank (no
    /// label fallback) — the arrow and compass letter carry the cell alone.
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

    /// The altitude page carries the live gradient in its caption line, like the direction cell's
    /// street: data in place of the name. But the gradient is nil more often than not (standstill,
    /// window not yet full), so nil falls back to the page's name, not a blank — a bare number over
    /// a blank line wouldn't say what it is.
    private var altitudeCell: StatCell {
        StatCell(
            systemImage: currentAltitudePage.systemImage,
            value: altitudeCellValue,
            captionContent: altitudeCaption,
            paging: .init(page: altitudePageIndex, names: altitudePages.map(\.name)),
            pageIndicatorInset: bottomRowIndicatorInset
        )
    }

    private var altitudePages: [AltitudeCellPage] {
        AltitudeCellPage.pages(tripState: trip.state)
    }

    /// A Reset takes climb and descent away underneath whoever was reading one, so the page the cell
    /// *shows* falls back to altitude while `altitudePage` keeps what the rider chose — start another
    /// trip and their readout comes back.
    private var currentAltitudePage: AltitudeCellPage {
        altitudePages.contains(altitudePage) ? altitudePage : .altitude
    }

    /// `StatCell` pages by index (dots, wrap-around, the swipe); the cell's state is the readout. This
    /// is the join between the two, and the reason no index ever outlives the page set it came from.
    private var altitudePageIndex: Binding<Int> {
        let pages = altitudePages
        let selection = $altitudePage
        let current = currentAltitudePage
        return Binding(
            get: { pages.firstIndex(of: current) ?? 0 },
            set: { selection.wrappedValue = pages[$0] }
        )
    }

    private var altitudeCaption: StatCell.Caption {
        guard currentAltitudePage == .altitude, let formattedGrade else { return .name }
        return .data(formattedGrade)
    }

    private var altitudeCellValue: String {
        // "--" rather than "0 m" throughout: a trip with no altitude data hasn't measured a flat
        // ride, it hasn't measured anything.
        switch currentAltitudePage {
        case .altitude:
            return location.altitude.map { measurementSystem.formattedAltitude(meters: $0, locale: locale) } ?? "--"
        case .climb:
            return trip.totalAscent.map { measurementSystem.formattedAltitude(meters: $0, locale: locale) } ?? "--"
        case .descent:
            return trip.totalDescent.map { measurementSystem.formattedAltitude(meters: $0, locale: locale) } ?? "--"
        case .position:
            return formattedPosition
        }
    }

    /// "▲ 4 %" climbing, "▼ 4 %" descending, bare "0 %" on the flat. Rounded to whole percent (a
    /// gradient's decimals are noise to a rider) *before* the arrow is chosen: the raw sign flaps
    /// around zero on flat ground, and pairing it with a rounded magnitude would show a
    /// self-contradictory "▼ 0 %".
    private var formattedGrade: String? {
        guard let grade = trip.grade else { return nil }
        let wholePercent = (abs(grade) * 100).rounded()
        let magnitude = (wholePercent / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
        guard wholePercent > 0 else { return magnitude }
        let arrow = grade < 0 ? "▼" : "▲"
        return "\(arrow) \(magnitude)"
    }

    /// The bezel is stroked over the panel's outer edge, eating into the bottom row's cells in a way
    /// the hairline divider above them doesn't. Without this extra inset the bottom dots would read
    /// as crowded against the bezel while the top row's sat clear above the divider.
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
                state: .running,
                averageSpeed: 6.86,
                maxSpeed: 11.4,
                distance: 28_560,
                duration: 4_324,
                totalAscent: 312,
                totalDescent: 287,
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
