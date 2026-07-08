import SwiftUI

/// Sheet-presented list of saved trips, newest first. Each row shows only a few details (date,
/// distance, duration); tapping a row pushes to `TripLogDetailView` for the full breakdown.
struct TripLogListView: View {
    @ObservedObject var store: TripLogStore

    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView("No trips logged yet", systemImage: "list.bullet.clipboard")
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            NavigationLink(value: entry) {
                                row(for: entry)
                            }
                        }
                        .onDelete { offsets in
                            store.delete(at: offsets)
                        }
                    }
                }
            }
            .navigationDestination(for: TripLogEntry.self) { entry in
                TripLogDetailView(entry: entry)
            }
            .navigationTitle(settingsStore.appLanguage.localizedString(forKey: "Trip Log"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for entry: TripLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            HStack(spacing: 12) {
                Label(settingsStore.measurementSystem.formattedDistance(meters: entry.distance, locale: locale), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(TripDurationFormatting.formatted(seconds: entry.duration, locale: locale), systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TripLogListView(store: TripLogStore())
        .environmentObject(SettingsStore())
}
