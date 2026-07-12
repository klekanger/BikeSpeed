import SwiftUI

/// One cell of the 2×2 stats grid: an SF Symbol on top with a value and a small caption below,
/// matching the "icon, then data" layout of the old stat rows. Cells can optionally be tapped to
/// toggle between two readouts (e.g. average↔max speed, altitude↔GPS position).
struct StatCell: View {
    let systemImage: String
    let value: String
    let caption: LocalizedStringKey
    /// Shown in place of `caption` when non-nil — for dynamic data that must not be run through the
    /// string catalog, like the reverse-geocoded street name in the direction cell. `caption` still
    /// supplies the VoiceOver label. An empty override renders a blank line rather than collapsing,
    /// so the cell's icon and value stay aligned with its neighbours in the grid.
    var captionOverride: String?
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

            captionText
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
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private var captionText: Text {
        guard let captionOverride else { return Text(caption) }
        // A space, not "", so the line still occupies its height and the cell doesn't reflow.
        return Text(captionOverride.isEmpty ? " " : captionOverride)
    }

    /// VoiceOver reads the label ("Direction of travel") plus this. A resolved override is data
    /// worth announcing, so it joins the value: "N, Storgata".
    private var accessibilityValue: String {
        guard let captionOverride, !captionOverride.isEmpty else { return value }
        return "\(value), \(captionOverride)"
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
