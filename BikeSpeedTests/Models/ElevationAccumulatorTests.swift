import Testing

@testable import BikeSpeed

/// The deadband is the whole design: noise must never add up to a climb, and a real climb must be
/// counted in full however slowly it is ridden.
struct ElevationAccumulatorTests {

    @Test(.tags(.edgeCase))
    func noiseInsideTheDeadbandAccumulatesNothing() {
        var accumulator = ElevationAccumulator(deadband: 1)
        for reading in 0..<200 {
            accumulator.add(altitude: 100 + (reading.isMultiple(of: 2) ? 0.4 : -0.4))
        }
        #expect(accumulator.ascent == 0)
        #expect(accumulator.descent == 0)
    }

    @Test
    func aRealClimbAccumulatesItsFullHeight() {
        var accumulator = ElevationAccumulator(deadband: 1)
        for altitude in stride(from: 100.0, through: 150.0, by: 2.0) {
            accumulator.add(altitude: altitude)
        }
        expectClose(accumulator.ascent, 50, within: 0.001)
        #expect(accumulator.descent == 0)
    }

    /// A long drag climbed in steps each too small to cross the deadband must still register: the anchor
    /// only moves when the threshold is crossed, so sub-deadband deltas keep measuring against it until
    /// together they do.
    @Test(.tags(.edgeCase))
    func aStaircaseOfSubDeadbandStepsStillRegisters() {
        var accumulator = ElevationAccumulator(deadband: 1)
        for altitude in stride(from: 100.0, through: 110.0, by: 0.5) {
            accumulator.add(altitude: altitude)
        }
        expectClose(accumulator.ascent, 10, within: 0.001)
    }

    @Test
    func climbAndDescentAreRecordedIndependently() {
        var accumulator = ElevationAccumulator(deadband: 1)
        for altitude in stride(from: 100.0, through: 120.0, by: 2.0) {
            accumulator.add(altitude: altitude)
        }
        for altitude in stride(from: 120.0, through: 90.0, by: -2.0) {
            accumulator.add(altitude: altitude)
        }
        expectClose(accumulator.ascent, 20, within: 0.001)
        expectClose(accumulator.descent, 30, within: 0.001)
    }

    /// What separates "a flat trip" (zero ascent) from "a trip with no altitude data at all" (nothing
    /// worth saving) once the trip is written to the log.
    @Test
    func recordsWhetherAnyAltitudeWasEverSampled() {
        var accumulator = ElevationAccumulator(deadband: 1)
        #expect(accumulator.hasRecordedAltitude == false)

        accumulator.add(altitude: 100)
        #expect(accumulator.hasRecordedAltitude)

        accumulator.reset()
        #expect(accumulator.hasRecordedAltitude == false)
    }

    /// The re-baseline used across breaks in sampling (a pause, a standstill, a restarted barometer):
    /// the readings on either side of a gap aren't comparable, so the difference between them must
    /// anchor fresh rather than be banked as climb — but everything already earned stays earned.
    @Test(.tags(.edgeCase))
    func reanchoringForgetsTheReferenceButKeepsTheTotals() {
        var accumulator = ElevationAccumulator(deadband: 1)
        accumulator.add(altitude: 100)
        accumulator.add(altitude: 110)
        expectClose(accumulator.ascent, 10, within: 0.001)

        accumulator.reanchor()

        accumulator.add(altitude: 50) // wildly discontinuous — must anchor, not bank -60 as descent
        #expect(accumulator.descent == 0)
        #expect(accumulator.hasRecordedAltitude, "re-baselining is not the same as never having data")

        accumulator.add(altitude: 56)
        expectClose(accumulator.ascent, 16, within: 0.001, "the accumulator keeps working after a reanchor")
    }

    @Test
    func resetClearsTheTotalsAndTheAnchor() {
        var accumulator = ElevationAccumulator(deadband: 1)
        for altitude in stride(from: 100.0, through: 120.0, by: 2.0) {
            accumulator.add(altitude: altitude)
        }

        accumulator.reset()

        #expect(accumulator.ascent == 0)
        #expect(accumulator.descent == 0)
    }
}
