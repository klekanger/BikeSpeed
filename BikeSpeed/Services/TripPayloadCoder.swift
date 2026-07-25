import Foundation

/// The one encoding the payload blobs use — and the same `RouteFileStore` used before them: ISO-8601
/// dates, default key strategy.
///
/// That identity is load-bearing: it lets `LegacyTripLogImporter` copy a legacy `Routes/<uuid>.json`
/// straight into `StoredTrip.routeData` **as bytes**, with no decode/re-encode round trip that could
/// change the last digit of a coordinate or drop a sample.
nonisolated enum TripPayloadCoder {
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
