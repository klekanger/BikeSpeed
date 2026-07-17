import Foundation
import Testing

@testable import BikeSpeed

/// A compass bearing wraps at 360°, but a view animating `.rotationEffect` lerps the degree figure
/// linearly — handed 359° then 1° it sweeps a half-turn through south. `ContinuousBearing` unwinds the
/// stream so consecutive angles never jump more than 180°, and the animation always takes the short way.
/// Every test here is that one arrow-whips-through-south bug, from a different side.
@Suite
struct ContinuousBearingTests {

    /// With nothing to unwind against, the first bearing is passed through untouched.
    @Test
    func theFirstBearingIsTakenAsIs() {
        var bearing = ContinuousBearing()
        expectClose(bearing.update(137), 137, within: 0.001)
        expectClose(bearing.degrees, 137, within: 0.001)
    }

    /// **The whole reason the type exists.** Crossing north 359° → 1° must step *forward* by two degrees
    /// to 361 (which renders as 1° but animates the short way), never backward to 1 through south.
    @Test(.tags(.edgeCase))
    func crossingNorthUpwardStepsForwardPastThreeSixty() {
        var bearing = ContinuousBearing()
        bearing.update(359)
        expectClose(bearing.update(1), 361, within: 0.001)
    }

    /// The mirror case: crossing north the other way, 1° → 359°, must step *back* to -1, not forward
    /// 358° through south.
    @Test(.tags(.edgeCase))
    func crossingNorthDownwardStepsBackPastZero() {
        var bearing = ContinuousBearing()
        bearing.update(1)
        expectClose(bearing.update(359), -1, within: 0.001)
    }

    /// A run of crossings accumulates without bound — two laps north keep climbing rather than
    /// snapping back — while every value still renders to the right compass heading (mod 360).
    @Test(.tags(.edgeCase))
    func repeatedCrossingsAccumulateFreely() {
        var bearing = ContinuousBearing()
        bearing.update(350)
        bearing.update(10)  // +20 → 370
        bearing.update(350) // -20 → 350
        bearing.update(10)  // +20 → 370
        expectClose(bearing.degrees, 370, within: 0.001)
        // 370° and 10° point the same way; the point is the *path*, not the endpoint.
        let onCompass = (bearing.degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        expectClose(onCompass, 10, within: 0.001)
    }

    /// An ordinary step nowhere near the wrap point is left exactly as it is — the unwinding must not
    /// perturb the common case.
    @Test
    func anInteriorStepIsUnchanged() {
        var bearing = ContinuousBearing()
        bearing.update(90)
        expectClose(bearing.update(120), 120, within: 0.001)
    }

    /// The 180° antipode is the tie-break boundary: a delta of exactly +180 is kept as forward motion,
    /// so a half-turn is well-defined rather than oscillating on rounding.
    @Test(.tags(.edgeCase))
    func theExactAntipodeStepsForward() {
        var bearing = ContinuousBearing()
        bearing.update(0)
        expectClose(bearing.update(180), 180, within: 0.001)
    }
}
