import SwiftUI

/// One cell of the 2×2 stats grid: an SF Symbol on top with a value and a small caption below,
/// matching the "icon, then data" layout of the old stat rows. Cells can optionally be tapped to
/// toggle between two readouts (e.g. average↔max speed, altitude↔GPS position).
struct StatCell: View {
    let systemImage: String
    let value: String
    let caption: LocalizedStringKey
    /// Rotation applied to the icon — used by the direction cell to point the arrow at the GPS
    /// course; `.zero` (the default) leaves ordinary stat icons upright.
    var iconRotation: Angle = .zero
    var iconTint: Color = .orange
    /// When non-nil the cell is tappable and this fires; the caller flips whatever state decides
    /// which readout is shown.
    var onTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(iconTint)
                .rotationEffect(iconRotation)
                .animation(.easeInOut(duration: 0.3), value: iconRotation)
                .accessibilityHidden(true)

            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(Text(value))
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }
}

#Preview {
    ZStack {
        Color.black
        HStack {
            StatCell(systemImage: "speedometer", value: "24.7 km/h", caption: "Average speed")
            StatCell(systemImage: "location.north.fill", value: "NE", caption: "Direction", iconRotation: .degrees(45))
        }
        .frame(height: 120)
    }
    .ignoresSafeArea()
}
