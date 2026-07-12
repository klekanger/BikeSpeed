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
        /// A fixed catalog string in place of the name, as the distance cell shows "Auto-paused".
        /// Unlike `.data` this stays a `LocalizedStringKey`, so SwiftUI resolves it against the
        /// in-app language override — no manual bundle lookup on every render.
        case text(LocalizedStringKey)
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
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private var captionText: Text {
        switch captionContent {
        case .name:
            return Text(caption)
        case .data(let text):
            // A space, not "", so an unresolved line still occupies its height and nothing reflows.
            return Text(verbatim: text ?? " ")
        case .text(let key):
            return Text(key)
        }
    }

    /// VoiceOver reads the label ("Direction of travel") plus this. A resolved caption is worth
    /// announcing, so it joins the value: "N, Storgata" / "0:45, Auto-paused". A `Text` rather than
    /// a `String` so the `.text` case can stay a `LocalizedStringKey` for SwiftUI to resolve.
    private var accessibilityValue: Text {
        switch captionContent {
        case .name:
            return Text(value)
        case .data(let text):
            guard let text else { return Text(value) }
            return Text(value) + Text(verbatim: ", ") + Text(verbatim: text)
        case .text(let key):
            return Text(value) + Text(verbatim: ", ") + Text(key)
        }
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
