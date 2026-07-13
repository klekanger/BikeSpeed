import SwiftUI

/// One cell of the 2×2 stats grid: an SF Symbol on top with a value and a small caption below,
/// matching the "icon, then data" layout of the old stat rows. A cell with more than one readout
/// (e.g. average↔max speed, altitude↔GPS position) is paged through by tapping or swiping it, and
/// says so with a page indicator.
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

    /// A cell the user can page through. Nil on a single-readout cell — the direction cell — which
    /// is then neither interactive nor marked with a page indicator. That absence is the whole
    /// signal: dots mean "there is more here", so a cell without them must have nothing to show.
    struct Paging {
        let page: Binding<Int>
        /// Every readout's name, in page order. The single source of the dot count, the caption
        /// line, the VoiceOver label and the hint, so no call site has to name a readout twice.
        let names: [LocalizedStringKey]

        var currentName: LocalizedStringKey { names[page.wrappedValue] }
        var nextName: LocalizedStringKey { names[(page.wrappedValue + 1) % names.count] }
    }

    let systemImage: String
    let value: String
    /// The stat's name, for a cell with a single readout. A paging cell leaves this nil and takes
    /// its name from the page it's showing instead.
    var caption: LocalizedStringKey?
    var captionContent: Caption = .name
    /// Rotation applied to the icon — used by the direction cell to point the arrow at the GPS
    /// course; `.zero` (the default) leaves ordinary stat icons upright.
    var iconRotation: Angle = .zero
    var iconTint: Color = .orange
    var paging: Paging?
    /// How far the page indicator sits above the cell's bottom edge. A cell whose bottom edge is
    /// covered by something — the panel's bezel is drawn over its outer 5pt — passes more, so its
    /// dots stand as far clear of that as everyone else's stand clear of a bare edge.
    var pageIndicatorInset: CGFloat = StatCell.defaultPageIndicatorInset

    static let defaultPageIndicatorInset: CGFloat = 8

    /// The gestures, the haptic and the activation action hang off the paging branch alone, so a
    /// single-readout cell neither swallows a tap nor tells VoiceOver it can be activated.
    @ViewBuilder var body: some View {
        if let paging {
            readout
                .contentShape(Rectangle())
                // A tap and a 24pt drag can't both match, so the two gestures need no arbitrating —
                // and neither is a Button, which would fire its action *and* the drag on a swipe.
                .onTapGesture { advance(by: 1) }
                .gesture(
                    DragGesture(minimumDistance: 24).onEnded { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                        advance(by: drag.translation.width < 0 ? 1 : -1)
                    }
                )
                .sensoryFeedback(.selection, trigger: paging.page.wrappedValue)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityValue(accessibilityValue)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Shows \(Text(paging.nextName))"))
                // A view driven by gestures rather than a Button gets no activation action for free.
                .accessibilityAction { advance(by: 1) }
        } else {
            readout
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityValue(accessibilityValue)
        }
    }

    private var readout: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(iconTint)
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(iconRotation)
                .animation(.easeInOut(duration: 0.3), value: iconRotation)
                .accessibilityHidden(true)

            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)

            captionText
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { pageIndicator }
    }

    /// A value that breaks across two lines — the GPS position, which is the one readout built with
    /// a newline in it — fills the cell top to bottom and crowds the caption under it. Two lines of
    /// this are still wider than any one-line readout, so it shrinks rather than the cell growing.
    private var valueFontSize: CGFloat {
        value.contains("\n") ? 16 : 20
    }

    /// The stat's name: the caption line's content unless `captionContent` replaces it, and always
    /// the VoiceOver label.
    private var name: LocalizedStringKey {
        paging?.currentName ?? caption ?? ""
    }

    /// Nothing to indicate on a single-readout cell — see `Paging`.
    @ViewBuilder private var pageIndicator: some View {
        if let paging {
            HStack(spacing: 5) {
                ForEach(0..<paging.names.count, id: \.self) { index in
                    Circle()
                        .fill(.white)
                        .opacity(index == paging.page.wrappedValue ? 0.85 : 0.25)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.bottom, pageIndicatorInset)
            .accessibilityHidden(true)
        }
    }

    private var captionText: Text {
        switch captionContent {
        case .name:
            return Text(name)
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

    /// Wraps at the ends, so a tap on the last page returns to the first.
    private func advance(by delta: Int) {
        guard let paging else { return }
        let count = paging.names.count
        // The only transaction that ever animates this cell: live values arrive on every GPS fix
        // and must keep landing instantly, so the content transitions above stay dormant until here.
        withAnimation(.easeInOut(duration: 0.25)) {
            paging.page.wrappedValue = (paging.page.wrappedValue + delta + count) % count
        }
    }
}

#Preview {
    @Previewable @State var speedPage = 0

    ZStack {
        Color.black
        HStack {
            StatCell(
                systemImage: speedPage == 1 ? "gauge.with.dots.needle.100percent" : "speedometer",
                value: speedPage == 1 ? "41.2 km/h" : "24.7 km/h",
                paging: .init(page: $speedPage, names: ["Average speed", "Max speed"])
            )
            StatCell(
                systemImage: "location.north.fill",
                value: "NE",
                caption: "Direction of travel",
                iconRotation: .degrees(45)
            )
        }
        .frame(height: 120)
    }
    .ignoresSafeArea()
}
