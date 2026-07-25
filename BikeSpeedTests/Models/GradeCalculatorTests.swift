import Testing

@testable import BikeSpeed

/// Grade is rise over run across a trailing window of distance — never fix-to-fix, where a ~5 m distance
/// delta against ±1 m of altitude noise is meaningless.
struct GradeCalculatorTests {

    @Test
    func gradeIsNilUntilTheWindowFills() {
        var calculator = GradeCalculator(windowDistance: 30)
        calculator.add(distance: 0, altitude: 100)
        calculator.add(distance: 10, altitude: 100.5)
        calculator.add(distance: 20, altitude: 101)

        #expect(calculator.grade == nil, "20 m of riding cannot fill a 30 m window")
    }

    @Test
    func aSteadyClimbReadsItsTrueSlope() throws {
        var calculator = GradeCalculator(windowDistance: 30)
        for step in 0...8 {
            calculator.add(distance: Double(step) * 10, altitude: 100 + Double(step) * 0.5) // 5 %
        }

        expectClose(try #require(calculator.grade), 0.05, within: 0.001)
    }

    @Test
    func flatGroundReadsZero() throws {
        var calculator = GradeCalculator(windowDistance: 30)
        for step in 0...8 {
            calculator.add(distance: Double(step) * 10, altitude: 100)
        }

        expectClose(try #require(calculator.grade), 0, within: 0.001)
    }

    @Test
    func aDescentReadsNegative() throws {
        var calculator = GradeCalculator(windowDistance: 30)
        for step in 0...8 {
            calculator.add(distance: Double(step) * 10, altitude: 100 - Double(step) * 0.8) // -8 %
        }

        expectClose(try #require(calculator.grade), -0.08, within: 0.001)
    }

    /// The window slides: a hill crested 60 m ago must not still be reported as the current gradient.
    @Test(.tags(.edgeCase))
    func anOldClimbFallsOutOfTheWindow() throws {
        var calculator = GradeCalculator(windowDistance: 30)
        for step in 0...4 {
            calculator.add(distance: Double(step) * 10, altitude: 100 + Double(step)) // 40 m at 10 %
        }
        for step in 1...6 {
            calculator.add(distance: 40 + Double(step) * 10, altitude: 104) // then 60 m dead flat
        }

        expectClose(try #require(calculator.grade), 0, within: 0.001)
    }

    @Test
    func resetForgetsTheRideSoFar() {
        var calculator = GradeCalculator(windowDistance: 30)
        for step in 0...8 {
            calculator.add(distance: Double(step) * 10, altitude: 100 + Double(step) * 0.5)
        }

        calculator.reset()

        #expect(calculator.grade == nil)
        calculator.add(distance: 0, altitude: 200)
        #expect(calculator.grade == nil, "the old samples must not survive into the next trip")
    }
}
