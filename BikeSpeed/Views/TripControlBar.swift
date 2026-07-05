import SwiftUI

struct TripControlBar: View {
    @ObservedObject var tripManager: TripManager

    var body: some View {
        HStack(spacing: 16) {
            Button(action: primaryAction) {
                Label(primaryLabel, systemImage: primaryIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button(role: .destructive, action: { tripManager.reset() }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(tripManager.state == .running)
        }
        .font(.system(size: 17, weight: .semibold))
        .padding(.horizontal)
    }

    private var primaryLabel: LocalizedStringKey {
        switch tripManager.state {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var primaryIcon: String {
        switch tripManager.state {
        case .idle, .paused: return "play.fill"
        case .running: return "pause.fill"
        }
    }

    private func primaryAction() {
        switch tripManager.state {
        case .idle: tripManager.start()
        case .running: tripManager.pause()
        case .paused: tripManager.resume()
        }
    }
}

#Preview {
    ZStack {
        Color.black
        TripControlBar(tripManager: TripManager(locationManager: LocationManager()))
    }
    .ignoresSafeArea()
}
