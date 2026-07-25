import Testing

@testable import BikeSpeed

@Suite(.tags(.gps))
struct CompassDirectionTests {
    /// The middle of each 45° sector maps to that sector's direction.
    @Test(arguments: zip(
        [0.0, 45, 90, 135, 180, 225, 270, 315],
        [CompassDirection.n, .ne, .e, .se, .s, .sw, .w, .nw]
    ))
    func sectorMidpointMapsToItsDirection(course: Double, expected: CompassDirection) {
        #expect(CompassDirection(course: course) == expected)
    }

    /// North straddles 0°, so its sector runs 337.5°..<22.5° — the one boundary that wraps, and the
    /// one a naive `course / 45` would get wrong.
    @Test(.tags(.edgeCase), arguments: zip(
        [337.5, 350.0, 359.9, 0.0, 22.4],
        [CompassDirection.n, .n, .n, .n, .n]
    ))
    func northSectorWrapsAroundZero(course: Double, expected: CompassDirection) {
        #expect(CompassDirection(course: course) == expected)
    }

    /// 22.5° is the first bearing that belongs to NE rather than N.
    @Test(.tags(.edgeCase))
    func sectorBoundaryRoundsUpToTheNextDirection() {
        #expect(CompassDirection(course: 22.4) == .n)
        #expect(CompassDirection(course: 22.5) == .ne)
    }

    /// `CLLocation.course` should never be negative or beyond 360, but the initializer normalizes
    /// rather than trapping, and that promise is worth holding it to.
    @Test(.tags(.edgeCase), arguments: zip(
        [-45.0, -90.0, 405.0, 720.0],
        [CompassDirection.nw, .w, .ne, .n]
    ))
    func coursesOutsideZeroTo360AreNormalized(course: Double, expected: CompassDirection) {
        #expect(CompassDirection(course: course) == expected)
    }
}
