import Foundation
import Testing

@testable import BikeSpeed

/// A compass bearing is an angle, not a number: 359° and 1° are two degrees apart, but a plain exponential
/// mean over those figures reads them as 358 apart and smooths *the long way round*, swinging the arrow
/// through south every time the rider crosses north. Every test here is really that one bug, from a
/// different side.
@Suite
struct CircularMeanTests {

    /// With nothing to average against, the first bearing is the answer — an arrow that eased in from an
    /// arbitrary zero would point at nothing real for the first second of every stop.
    @Test
    func theFirstBearingIsTakenAsIs() throws {
        var mean = CircularMean(smoothingFactor: 0.25)

        expectClose(mean.add(137), 137, within: 0.001)
        expectClose(try #require(mean.value), 137, within: 0.001)
    }

    /// **The whole reason the type exists.** Smoothing from 359° toward 1° must move *forwards* through
    /// north — 359 → 0 → 1 — and never take the 358° journey backwards through south.
    @Test(.tags(.edgeCase))
    func smoothingAcrossNorthTakesTheShortWayRound() {
        var mean = CircularMean(smoothingFactor: 0.5)
        _ = mean.add(359)

        let smoothed = mean.add(1)

        // Halfway from 359° to 1° is 0° — due north. Compared as a circular distance, so that an answer of
        // 360 (the same bearing, written differently) passes and 180 (the long way round) cannot.
        expectClose(circularDistance(smoothed, 0), 0, within: 0.5)
    }

    /// The same crossing, walked step by step: no intermediate value may ever land in the southern half of
    /// the compass. A degrees-space mean would put every one of them there.
    @Test(.tags(.edgeCase))
    func noStepOfANorthCrossingEverSwingsThroughSouth() throws {
        var mean = CircularMean(smoothingFactor: 0.3)
        _ = mean.add(350)

        for _ in 0..<20 {
            let smoothed = mean.add(10)
            #expect(
                circularDistance(smoothed, 0) <= 90,
                "smoothing 350° toward 10° left the northern half at \(smoothed)° — it went the long way"
            )
        }

        expectClose(circularDistance(try #require(mean.value), 10), 0, within: 1)
    }

    @Test
    func repeatedBearingsConvergeOnThatBearing() throws {
        var mean = CircularMean(smoothingFactor: 0.4)
        _ = mean.add(90)

        for _ in 0..<50 { _ = mean.add(270) }

        expectClose(circularDistance(try #require(mean.value), 270), 0, within: 0.5)
    }

    /// A lower factor must lag further behind a new bearing than a higher one — that is what "smoothing"
    /// means, and it's what keeps a jittering magnetometer from twitching the arrow.
    @Test
    func aSmallerFactorLagsFurtherBehindANewBearing() {
        var sluggish = CircularMean(smoothingFactor: 0.1)
        var eager = CircularMean(smoothingFactor: 0.9)
        _ = sluggish.add(0)
        _ = eager.add(0)

        let sluggishStep = sluggish.add(90)
        let eagerStep = eager.add(90)

        #expect(sluggishStep < eagerStep)
        #expect(sluggishStep > 0)
        #expect(eagerStep < 90)
    }

    /// Output is a bearing, so it has to stay inside the compass — a consumer rotating an arrow by -3° or
    /// 361° would be relying on `rotationEffect` to be forgiving.
    @Test(.tags(.edgeCase))
    func theSmoothedBearingIsAlwaysInsideZeroToThreeSixty() {
        var mean = CircularMean(smoothingFactor: 0.35)
        _ = mean.add(1)

        for bearing in stride(from: 350.0, through: 359.0, by: 1.0) {
            let smoothed = mean.add(bearing)
            #expect(smoothed >= 0 && smoothed < 360, "\(smoothed)° is not a bearing")
        }
    }

    @Test
    func resetForgetsTheBearingSoTheNextOneIsTakenAsIs() {
        var mean = CircularMean(smoothingFactor: 0.2)
        _ = mean.add(10)

        mean.reset()

        #expect(mean.value == nil)
        expectClose(mean.add(200), 200, within: 0.001)
    }

    // MARK: - Helpers

    /// Shortest angular distance between two bearings, 0…180. The comparison every assertion above needs:
    /// in degrees-space 359 and 1 look 358 apart, which is exactly the mistake under test.
    private func circularDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}
