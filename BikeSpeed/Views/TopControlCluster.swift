import SwiftUI

/// The top-right navigation cluster: a single neutral capsule holding the app's screen-level
/// destinations. Chrome, deliberately — it uses a translucent material and `.secondary` tones so it
/// recedes and the orange gauge keeps the eye (an orange button up here fought the needle/danger-arc
/// for attention). Symmetric icon buttons read as one designed control rather than two loose glyphs.
///
/// **This is the growth point.** New screen-level destinations (a Pro upsell, a stats screen) are added
/// as another `clusterButton`. Once the cluster would hold more than ~three, fold the extras into a
/// `Menu` behind a trailing `ellipsis` button rather than widening the pill across the gauge.
struct TopControlCluster: View {
    let onTripLog: () -> Void
    let onSettings: () -> Void

    var body: some View {
        content
            .foregroundStyle(.secondary)
    }

    /// The glass pill itself. On iOS 26 it's true Liquid Glass so it matches `TripControlBar`; below,
    /// it falls back to a translucent material capsule that reads the same at a glance.
    @ViewBuilder
    private var content: some View {
        let buttons = HStack(spacing: 2) {
            clusterButton("Trips", systemImage: "list.bullet.rectangle.portrait", action: onTripLog)

            Divider()
                .frame(height: 22)

            clusterButton("Settings", systemImage: "gearshape.fill", action: onSettings)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)

        if #available(iOS 26.0, *) {
            buttons.glassEffect(.regular, in: .capsule)
        } else {
            buttons
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        }
    }

    private func clusterButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 19, weight: .medium))
            .frame(width: 40, height: 36)
            .contentShape(.rect)
            .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            HStack {
                Spacer()
                TopControlCluster(onTripLog: {}, onSettings: {})
                    .padding(12)
            }
            Spacer()
        }
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
