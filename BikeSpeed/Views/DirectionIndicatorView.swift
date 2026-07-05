import SwiftUI

/// Rotating arrow + 8-point compass abbreviation showing direction of travel (GPS course, not
/// device heading). `course` is nil while there has never been a reliable course reading yet,
/// in which case the arrow is dimmed and shown at its default orientation with "--".
struct DirectionIndicatorView: View {
    let course: Double?

    private var direction: CompassDirection? {
        course.map(CompassDirection.init(course:))
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 22))
                .rotationEffect(.degrees(course ?? 0))
                .foregroundStyle(course == nil ? Color.secondary : Color.orange)
                .animation(.easeInOut(duration: 0.3), value: course)

            Text(direction?.abbreviation ?? "--")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Direction of travel")
        .accessibilityValue(direction.map { Text(verbatim: $0.abbreviation) } ?? Text("Unknown"))
    }
}

#Preview {
    ZStack {
        Color.black
        HStack(spacing: 24) {
            ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { course in
                DirectionIndicatorView(course: Double(course))
            }
            DirectionIndicatorView(course: nil)
        }
    }
    .ignoresSafeArea()
}
