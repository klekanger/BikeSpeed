import Testing

@testable import BikeSpeed

/// The altitude cell's page set is the one piece of the panel that changes shape at runtime: climb and
/// descent are trip stats and only exist once a trip has started. Getting it wrong either shows two
/// permanent "--" readouts or drops them mid-ride, so the page order and both shapes are pinned here.
@Suite
struct AltitudeCellPageTests {

    @Test
    func anIdleTripOffersOnlyTheLiveReadouts() {
        #expect(AltitudeCellPage.pages(tripState: .idle) == [.altitude, .position])
    }

    @Test(arguments: [TripState.running, .paused])
    func aStartedTripAddsClimbAndDescent(state: TripState) {
        #expect(AltitudeCellPage.pages(tripState: state) == [.altitude, .climb, .descent, .position])
    }

    /// Climb sits next to the altitude it accumulates from, and descent next to climb — the pair reads
    /// as one swipe. A reordering here silently rearranges the cell, so it's pinned rather than left
    /// to `CaseIterable`'s declaration order.
    @Test
    func climbAndDescentSitBetweenAltitudeAndPosition() {
        #expect(AltitudeCellPage.allCases == [.altitude, .climb, .descent, .position])
    }
}
