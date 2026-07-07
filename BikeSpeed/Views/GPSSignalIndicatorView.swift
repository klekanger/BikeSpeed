import SwiftUI

/// Top-left GPS signal indicator: a location glyph tinted green (good), yellow (fair), or red
/// (poor). A poor signal shows the crossed-out glyph, since in that state speed and distance are
/// frozen (see `LocationManager`).
struct GPSSignalIndicatorView: View {
    let quality: GPSSignalQuality

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(color)
            .animation(.easeInOut(duration: 0.3), value: quality)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("GPS signal")
            .accessibilityValue(accessibilityValue)
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
            GPSSignalIndicatorView(quality: .good)
            GPSSignalIndicatorView(quality: .fair)
            GPSSignalIndicatorView(quality: .poor)
        }
        .font(.system(size: 24))
    }
    .ignoresSafeArea()
}
