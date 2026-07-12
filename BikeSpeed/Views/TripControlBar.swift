import SwiftUI

struct TripControlBar: View {
    @ObservedObject var tripManager: TripManager
    @EnvironmentObject private var tripLogStore: TripLogStore

    @State private var isShowingSavedConfirmation = false

    var body: some View {
        Group {
            content
        }
        .alert("Trip saved", isPresented: $isShowingSavedConfirmation) {
            Button("OK") {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    Button(action: primaryAction) {
                        Label(primaryLabel, systemImage: primaryIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)

                    Button(action: saveAction) {
                        Label("Save", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(.green)
                    .disabled(!tripManager.canSaveTrip)

                    Button(role: .destructive, action: { tripManager.reset() }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(tripManager.state == .running)
                }
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal)
            }
        } else {
            HStack(spacing: 16) {
                Button(action: primaryAction) {
                    Label(primaryLabel, systemImage: primaryIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(action: saveAction) {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(!tripManager.canSaveTrip)

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

    private func saveAction() {
        guard let entry = tripManager.makeLogEntry() else { return }
        tripLogStore.save(entry)
        tripManager.reset()
        isShowingSavedConfirmation = true
    }
}

#Preview {
    ZStack {
        Color.black
        TripControlBar(tripManager: TripManager(locationManager: LocationManager(), settings: SettingsStore()))
            .environmentObject(TripLogStore())
    }
    .ignoresSafeArea()
}
