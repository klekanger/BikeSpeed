import SwiftUI

/// One cell of the 2×2 stats grid: an SF Symbol on top with a value and a small caption below,
/// matching the "icon, then data" layout of the old stat rows. Cells can optionally be tapped to
/// toggle between two readouts (e.g. average↔max speed, altitude↔GPS position).
struct StatCell: View {
    /// What the caption line under the value displays.
    enum Caption {
        /// The stat's own name — "Distance", "Altitude". The default for most cells.
        case name
        /// Live data in place of the name, as the direction cell shows the street being ridden.
        /// Nil renders a blank line rather than no line, so the cell stays vertically aligned with
        /// its neighbours in the grid until the data resolves.
        case data(String?)
    }

    let systemImage: String
    let value: String
    /// The stat's name: always the VoiceOver label, and the caption line's content unless
    /// `captionContent` replaces it.
    let caption: LocalizedStringKey
    var captionContent: Caption = .name
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
        switch captionContent {
        case .name:
            return Text(caption)
        case .data(let text):
            // A space, not "", so an unresolved line still occupies its height and nothing reflows.
            return Text(verbatim: text ?? " ")
        }
    }

    /// VoiceOver reads the label ("Direction of travel") plus this. Resolved data is worth
    /// announcing, so it joins the value: "N, Storgata".
    private var accessibilityValue: String {
        guard case .data(let text?) = captionContent else { return value }
        return "\(value), \(text)"
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
