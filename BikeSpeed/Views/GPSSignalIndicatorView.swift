import SwiftUI

/// Top-left GPS signal indicator: a location glyph tinted green (good), yellow (fair), or red
/// (poor). A poor signal shows the crossed-out glyph, since in that state speed and distance are
/// frozen (see `LocationManager`). While a trip is running, the glyph pulses slowly and a
/// "Logging" label appears to its right.
struct GPSSignalIndicatorView: View {
    let quality: GPSSignalQuality
    let isTracking: Bool

    @State private var isPulsing = false
    @State private var pulseTask: Task<Void, Never>?

    private static let pulseStepDuration = 1.2

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
                .opacity(isTracking && isPulsing ? 0.35 : 0.75)
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

    // `.repeatForever` animations run on the rendered layer rather than being driven by
    // `isPulsing`'s value, so simply setting `isPulsing = false` doesn't reliably cancel an
    // in-flight repeat. Driving each half-cycle explicitly from a cancellable Task means
    // stopping is just "don't schedule the next step" instead of racing a running animation.
    private func updatePulse() {
        pulseTask?.cancel()
        guard isTracking else {
            withAnimation(.easeInOut(duration: 0.3)) {
                isPulsing = false
            }
            return
        }

        pulseTask = Task {
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: Self.pulseStepDuration)) {
                    isPulsing.toggle()
                }
                try? await Task.sleep(for: .seconds(Self.pulseStepDuration))
            }
        }
    }

    private var symbolName: String {
        switch quality {
        case .good, .fair: return "location.circle.fill"
        case .poor: return "location.slash.circle.fill"
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
