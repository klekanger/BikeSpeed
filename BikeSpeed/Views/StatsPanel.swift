import SwiftUI
import CoreLocation

struct StatsPanel: View {
    let averageSpeed: Double // m/s
    let distance: Double // meters
    let altitude: Double? // meters
    let coordinate: CLLocationCoordinate2D?
    let measurementSystem: MeasurementSystem

    var body: some View {
        VStack(spacing: 10) {
            StatRow(
                systemImage: "speedometer",
                label: "Average speed",
                value: measurementSystem.formattedSpeed(metersPerSecond: averageSpeed)
            )
            StatRow(
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                label: "Distance",
                value: measurementSystem.formattedDistance(meters: distance)
            )
            StatRow(
                systemImage: "mountain.2",
                label: "Altitude",
                value: altitude.map(measurementSystem.formattedAltitude) ?? "--"
            )
            StatRow(
                systemImage: "location",
                label: "Position",
                value: formattedPosition
            )
        }
    }

    private var formattedPosition: String {
        guard let coordinate else { return "--" }
        let latHemisphere = coordinate.latitude >= 0 ? "N" : "S"
        let lonHemisphere = coordinate.longitude >= 0 ? "E" : "W"
        let lat = String(format: "%.6f°", abs(coordinate.latitude))
        let lon = String(format: "%.6f°", abs(coordinate.longitude))
        return "\(lat) \(latHemisphere)\n \(lon) \(lonHemisphere)"
    }
}

#Preview {
    ZStack {
        Color.black
        StatsPanel(
            averageSpeed: 6.86,
            distance: 28_560,
            altitude: 145,
            coordinate: CLLocationCoordinate2D(latitude: 59.913868, longitude: 10.752245),
            measurementSystem: .metric
        )
        .padding()
    }
    .ignoresSafeArea()
}
