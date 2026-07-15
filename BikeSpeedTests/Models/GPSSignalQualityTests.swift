import CoreLocation
import Testing

@testable import BikeSpeed

/// The band boundaries drive the signal dot on the gauge, and — through `isUsable` — whether a fix is
/// trusted at all. Both edges are pinned, since an off-by-one here either throws away good fixes or lets
/// noise into the trip.
@Suite(.tags(.gps))
struct GPSSignalQualityTests {

    @Test(arguments: zip(
        [5.0, 10.0, 11.0, 30.0, 31.0, -1.0],
        [GPSSignalQuality.good, .good, .fair, .fair, .poor, .poor]
    ))
    func signalQualityBucketsHorizontalAccuracy(accuracy: CLLocationAccuracy, expected: GPSSignalQuality) {
        let quality = GPSSignalQuality(horizontalAccuracy: accuracy, goodWithin: 10, acceptableWithin: 30)
        #expect(quality == expected)
    }

    @Test
    func onlyPoorSignalIsUnusable() {
        #expect(GPSSignalQuality.good.isUsable)
        #expect(GPSSignalQuality.fair.isUsable)
        #expect(GPSSignalQuality.poor.isUsable == false)
    }
}
