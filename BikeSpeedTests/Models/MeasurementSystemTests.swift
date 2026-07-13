import Foundation
import Testing

@testable import BikeSpeed

/// The model layer is SI throughout and only the view layer converts, so these conversions sit on the
/// boundary where a mistake would be visible on the gauge but invisible in the data.
struct MeasurementSystemTests {

    @Test(arguments: zip(
        [0.0, 8.0, 10.0, 27.7778],
        [0.0, 28.8, 36.0, 100.0]
    ))
    func metricConvertsMetersPerSecondToKilometersPerHour(mps: Double, kmh: Double) {
        expectClose(MeasurementSystem.metric.speedValue(metersPerSecond: mps), kmh, within: 0.01)
    }

    @Test(arguments: zip(
        [0.0, 8.0, 26.8224],
        [0.0, 17.8956, 60.0]
    ))
    func imperialConvertsMetersPerSecondToMilesPerHour(mps: Double, mph: Double) {
        expectClose(MeasurementSystem.imperial.speedValue(metersPerSecond: mps), mph, within: 0.01)
    }

    /// The gauge maximum is stored canonically in km/h no matter which unit is on screen, so switching
    /// units must not drift the stored value. The Settings stepper round-trips through this on every tap.
    @Test(.tags(.edgeCase), arguments: [MeasurementSystem.metric, .imperial])
    func theGaugeMaximumRoundTripsThroughItsDisplayUnit(system: MeasurementSystem) {
        let canonical = 60.0

        let displayed = system.maxGaugeSpeedValue(fromCanonicalKMH: canonical)
        let restored = system.canonicalKMH(fromMaxGaugeSpeedValue: displayed)

        expectClose(restored, canonical, within: 0.001)
    }

    /// Foundation renders this unit as "km/hr" in English and "mile/t" in Norwegian, neither of which is
    /// what a rider expects to see in the middle of a speedometer — hence the hand-picked labels.
    @Test
    func theGaugeUnitLabelUsesTheAbbreviationRidersExpect() {
        #expect(MeasurementSystem.metric.gaugeUnitLabel(locale: Locale(identifier: "en")) == "KM/H")
        #expect(MeasurementSystem.metric.gaugeUnitLabel(locale: Locale(identifier: "nb")) == "KM/T")
        #expect(MeasurementSystem.imperial.gaugeUnitLabel(locale: Locale(identifier: "en")) == "MPH")
        #expect(MeasurementSystem.imperial.gaugeUnitLabel(locale: Locale(identifier: "nb")) == "MPH")
    }
}
