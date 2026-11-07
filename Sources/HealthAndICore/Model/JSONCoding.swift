import Foundation

/// Shared JSON configuration for every file Health&I reads or writes.
///
/// Keys are snake_case via explicit `CodingKeys` raw values rather than
/// `.convertToSnakeCase` / `.convertFromSnakeCase`: Foundation applies key strategies to
/// `[String: _]` dictionary keys too, which would corrupt free-form keys such as
/// `limits["dumbbell_max_kg"]` on decode. The bytes on disk are the same snake_case JSON.
public enum JSONCoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

extension KeyedDecodingContainer {
    func opt<T: Decodable>(_ key: Key) throws -> T? {
        try decodeIfPresent(T.self, forKey: key)
    }

    func val<T: Decodable>(_ key: Key, _ fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
