import Foundation

/// The `Routes/` directory and everything that touches it, split out of `TripLogStore` so a track can be
/// read and written **off the main actor**.
///
/// `TripLogStore` is `@MainActor` because the trip list binds to its `entries`, and under this project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a route read there is a synchronous JSON decode on the run
/// loop. A track is not small — a long ride is thousands of samples — so that decode, and the GPX render
/// that follows it, would stall the detail view's first frame. `nonisolated` and `Sendable` is what lets
/// `TripLogDetailView` hand the whole job to a `Task.detached`.
///
/// It carries its own coder rather than sharing `TripLogStore`'s: those are main-actor state, and the
/// point of this type is to not be.
nonisolated struct RouteFileStore: Sendable {
    let directory: URL

    /// Nil for a trip that has no track — every trip saved before route recording shipped, and any trip
    /// whose route file failed to write or has since been reaped. Callers show the map only when there
    /// is one, so this is a normal answer rather than an error.
    func load(_ id: UUID) -> [RouteSample]? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? decoder().decode([RouteSample].self, from: data)
    }

    /// A failure here is not worth failing the trip's save over: the trip itself is already written, and
    /// a ride recorded without its map is far better than no ride at all.
    func save(_ route: [RouteSample], for id: UUID) {
        guard !route.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder().encode(route) else { return }
        try? data.write(to: url(for: id), options: .atomic)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Route files whose trip is gone. The log is the authority: `TripLogStore.load()` falls back to an
    /// empty array when the log won't decode, and the next `persist()` makes that permanent — taking with
    /// it the ids that name these files. Nothing else can ever reach them again.
    ///
    /// Only files named as a UUID are ever returned, so the caller can only delete what this type wrote.
    func orphans(keeping known: Set<UUID>) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { file in
            guard file.pathExtension == "json",
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            else { return false }
            return !known.contains(id)
        }
    }

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
