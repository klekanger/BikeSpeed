import SwiftUI

struct TripControlBar: View {
    /// A plain property: an `@Observable` is tracked wherever its properties are read in a body, so it
    /// needs no wrapper to stay live — only writing (`@Bindable`) or owning (`@State`) would.
    let tripManager: TripManager
    @Environment(TripDataStack.self) private var stack

    @State private var isShowingSavedConfirmation = false
    @State private var isShowingSaveFailure = false

    var body: some View {
        Group {
            content
        }
        .alert("Trip saved", isPresented: $isShowingSavedConfirmation) {
            Button("OK") {}
        }
        .alert("Couldn't save trip", isPresented: $isShowingSaveFailure) {
            Button("OK") {}
        } message: {
            Text("Your ride hasn't been lost — it's still paused. Try saving again.")
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
                    .disabled(!tripManager.canResetTrip)
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
                .disabled(!tripManager.canResetTrip)
            }
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal)
        }
    }

    /// An auto-paused trip has already stopped accumulating, so "Pause" would read as a no-op next to
    /// a panel saying "Auto-paused". The action still calls `pause()`, but here that takes the pause
    /// off the app and hands it to the rider — the end-of-ride gesture, since Save unlocks the moment
    /// the pause is manual. A Garmin labels the same button in the same state "Stop", for the same reason.
    private var primaryLabel: LocalizedStringKey {
        if tripManager.isAutoPaused { return "Stop" }
        switch tripManager.state {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var primaryIcon: String {
        if tripManager.isAutoPaused { return "stop.fill" }
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

    /// **Reset comes after the write, not before.** `reset()` throws away the only other copy of the
    /// ride, and the confirmation alert says it's safe — so neither happens until the store says the
    /// trip is on disk. If the save fails the trip is still paused and still theirs, and tapping Save
    /// again retries.
    private func saveAction() {
        guard let entry = tripManager.makeLogEntry() else { return }
        // Payloads travel alongside the entry, not inside it — see `TripLogEntry` for why the trip
        // list must never carry a ride's track.
        let profile = tripManager.altitudeProfile
        let route = tripManager.routeSamples

        Task {
            do {
                // Encode is O(samples) and runs off the main actor; the insert lands on the main
                // context, so the ride is in the trip list's `@Query` by the time this returns.
                try await stack.save(entry, altitudeProfile: profile, route: route)
                tripManager.reset()
                isShowingSavedConfirmation = true
            } catch {
                isShowingSaveFailure = true
            }
        }
    }
}

#Preview {
    let container = try! TripModelContainer.inMemory()
    return ZStack {
        Color.black
        TripControlBar(tripManager: TripManager(locationManager: LocationManager(), altimeter: AltimeterManager(), settings: SettingsStore()))
            .environment(TripDataStack(container: container))
    }
    .ignoresSafeArea()
}
