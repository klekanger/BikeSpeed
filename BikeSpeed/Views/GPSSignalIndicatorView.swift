import SwiftUI

/// Top-left GPS signal indicator: a location glyph tinted green (good), yellow (fair), or red
/// (poor). A poor signal shows the crossed-out glyph, since in that state speed and distance are
/// frozen (see `LocationManager`). While a trip is running, the glyph pulses slowly and a
/// "Logging" label appears to its right.
struct GPSSignalIndicatorView: View {
    let quality: GPSSignalQuality
    let isTracking: Bool

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
                .opacity(isTracking && isPulsing ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.3), value: quality)

            if isTracking {
                Text("Logging")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .onAppear { updatePulse() }
        .onChange(of: isTracking) { _, _ in updatePulse() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GPS signal")
        .accessibilityValue(accessibilityValue)
    }

    private func updatePulse() {
        if isTracking {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                isPulsing = false
            }
        }
    }

    private var symbolName: String {
        switch quality {
        case .good, .fair: return "location.fill"
        case .poor: return "location.slash.fill"
        }
    }

    private var color: Color {
        switch quality {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    private var accessibilityValue: LocalizedStringKey {
        switch quality {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}

#Preview {
    ZStack {
        Color.black
        HStack(spacing: 24) {
            GPSSignalIndicatorView(quality: .good, isTracking: false)
            GPSSignalIndicatorView(quality: .fair, isTracking: false)
            GPSSignalIndicatorView(quality: .poor, isTracking: true)
        }
        .font(.system(size: 24))
    }
    .ignoresSafeArea()
}
